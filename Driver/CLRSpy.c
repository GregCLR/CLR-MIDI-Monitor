#include <CoreMIDI/MIDIDriver.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <unistd.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include "CaptureTransport.h"

// IPC v1: request = token:u64, count:u32, destination refs:u32[].
// Response = magic:u32, status:u32, drops:u64, recordCount:u32,
// then endpoint:u32, timestamp:u64, arrival:u64, wordCount:u32, words:u32[].
// All values are native little-endian; driver/client ship together on macOS.
#ifndef CLR_SPY_PORT_FORMAT
#define CLR_SPY_PORT_FORMAT "com.clr.midimonitor.spy.v1.%u"
#endif
#define MAGIC 0x43535031
#define MAX_DEST 256
#define LEASE_SECONDS 3
typedef struct {
    MIDIDriverInterface *interface;
    UInt32 refs;
    CLRPacketQueue *queue;
    CFMessagePortRef port;
    CFRunLoopSourceRef source;
    CFRunLoopRef runLoop;
    uint64_t owner;
    _Atomic uint64_t deadline;
    _Atomic uint32_t destinations[MAX_DEST];
    uint64_t leaseTicks;
    _Atomic int monitorStatus;
    _Atomic bool stopping;
    pthread_t worker;
    pthread_mutex_t startupLock;
    pthread_cond_t startupCondition;
    bool workerStarted, startupFinished;
} Spy;
static MIDIDriverInterface interface;
static Spy *object(void *self) { return (Spy *)self; }
static void append(CFMutableDataRef data, const void *bytes, CFIndex length) { CFDataAppendBytes(data, bytes, length); }
static CFDataRef request(CFMessagePortRef port, SInt32 command, CFDataRef data, void *info) {
    Spy *s = info;
    CFMutableDataRef result = CFDataCreateMutable(NULL, 0);
    uint32_t magic = MAGIC, status = 0, count = 0;
    uint64_t drops = 0, token = 0;
    uint32_t wanted = 0;
    CFIndex length = data ? CFDataGetLength(data) : 0;
    const UInt8 *bytes = data ? CFDataGetBytePtr(data) : NULL;
    if (length >= 12) { memcpy(&token, bytes, 8); memcpy(&wanted, bytes+8, 4); }
    uint64_t now = mach_absolute_time();
    if (length < 12 || wanted > MAX_DEST || length != 12 + wanted * 4 || !token || (command != 1 && command != 2)) status = 3;
    else if (atomic_load(&s->stopping) || atomic_load(&s->monitorStatus) != noErr) status = 4;
    else if (s->owner && s->owner != token && now < atomic_load(&s->deadline)) status = 2;
    else {
        if (s->owner != token || now >= atomic_load(&s->deadline)) {
            atomic_store(&s->deadline, 0);
            CLRPacketRecord discarded;
            for (int i=0;i<512 && CLRQueuePop(s->queue,&discarded);i++) {}
            CLRQueueTakeDrops(s->queue);
        }
        s->owner = command == 2 ? 0 : token;
        if (command == 2 || wanted == 0) atomic_store(&s->deadline, 0);
        for (uint32_t i=0;i<MAX_DEST;i++) {
            uint32_t endpoint = 0;
            if (command == 1 && i < wanted) memcpy(&endpoint,bytes+12+i*4,4);
            atomic_store(&s->destinations[i], endpoint);
        }
        if (command == 1 && wanted) atomic_store(&s->deadline, now + s->leaseTicks);
        CLRDropCounts d = CLRQueueTakeDrops(s->queue);
        drops = d.full+d.contention+d.oversized;
    }
    append(result,&magic,4); append(result,&status,4); append(result,&drops,8); append(result,&count,4);
    if (status == 0 && command == 1) {
        CLRPacketRecord record;
        // Bound work per request; never let a busy producer monopolize MIDIServer.
        while (count < 64 && CLRQueuePop(s->queue,&record)) {
            append(result,&record.endpoint,4); append(result,&record.timestamp,8);
            append(result,&record.receivedAt,8); append(result,&record.wordCount,4);
            append(result,record.words,record.wordCount*4); count++;
        }
        CFDataReplaceBytes(result, CFRangeMake(16,4), (const UInt8 *)&count,4);
    }
    return result;
}
static HRESULT query(void *self, REFIID iid, LPVOID *out) {
    CFUUIDRef uuid = CFUUIDCreateFromUUIDBytes(NULL,iid);
    Boolean supported = CFEqual(uuid,kMIDIDriverInterface3ID) || CFEqual(uuid,IUnknownUUID);
    CFRelease(uuid); *out = supported ? self : NULL;
    if (!supported) return E_NOINTERFACE;
    object(self)->refs++; return S_OK;
}
static ULONG addRef(void *self) { return ++object(self)->refs; }
static void *serve(void *context) {
    Spy *s = context;
    CFStringRef name = CFStringCreateWithFormat(NULL,NULL,CFSTR(CLR_SPY_PORT_FORMAT),getuid());
    CFMessagePortContext portContext = {0,s,NULL,NULL,NULL};
    CFMessagePortRef port = CFMessagePortCreateLocal(NULL,name,request,&portContext,NULL);
    CFRelease(name);
    CFRunLoopSourceRef source = port ? CFMessagePortCreateRunLoopSource(NULL,port,0) : NULL;
    CFRunLoopRef runLoop = CFRunLoopGetCurrent();
    if (source) CFRunLoopAddSource(runLoop,source,kCFRunLoopDefaultMode);
    pthread_mutex_lock(&s->startupLock);
    s->port=port; s->source=source; s->runLoop=(CFRunLoopRef)CFRetain(runLoop);
    s->startupFinished=true;
    pthread_cond_signal(&s->startupCondition);
    pthread_mutex_unlock(&s->startupLock);
    // Bounded waits also cover Stop racing with the first CFRunLoopRun call.
    while (source && !atomic_load(&s->stopping)) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.1,true);
    if (source) { CFRunLoopRemoveSource(runLoop,source,kCFRunLoopDefaultMode); CFRelease(source); }
    if (port) { CFMessagePortInvalidate(port); CFRelease(port); }
    return NULL;
}
static OSStatus stop(MIDIDriverRef self) {
    Spy *s = object(self);
    atomic_store(&s->stopping,true); atomic_store(&s->deadline,0);
    MIDIDriverEnableMonitoring(self,false);
    if (s->workerStarted) {
        CFRunLoopStop(s->runLoop);
        pthread_join(s->worker,NULL); s->workerStarted=false;
    }
    if (s->runLoop) CFRelease(s->runLoop);
    s->runLoop=NULL; s->port=NULL; s->source=NULL; s->owner=0;
    return noErr;
}
static ULONG release(void *self) {
    Spy *s = object(self); UInt32 refs=--s->refs;
    if (!refs) {
        stop((MIDIDriverRef)self); CLRQueueDestroy(s->queue);
        pthread_cond_destroy(&s->startupCondition); pthread_mutex_destroy(&s->startupLock); free(s);
    }
    return refs;
}
static OSStatus start(MIDIDriverRef self, MIDIDeviceListRef devices) {
    Spy *s = object(self);
    if (s->workerStarted) return noErr;
    atomic_store(&s->stopping,false); s->startupFinished=false;
    if (pthread_create(&s->worker,NULL,serve,s) != 0) return -1;
    s->workerStarted=true;
    pthread_mutex_lock(&s->startupLock);
    while (!s->startupFinished) pthread_cond_wait(&s->startupCondition,&s->startupLock);
    pthread_mutex_unlock(&s->startupLock);
    if (!s->port || !s->source) { stop(self); return -1; }
    atomic_store(&s->monitorStatus,MIDIDriverEnableMonitoring(self,true));
    return noErr;
}
static OSStatus monitor(MIDIDriverRef self, MIDIEndpointRef dest, const MIDIEventList *list) {
    Spy *s = object(self);
    if (mach_absolute_time() >= atomic_load(&s->deadline)) return noErr;
    for (int i=0;i<MAX_DEST;i++) {
        if (atomic_load(&s->destinations[i]) == dest && dest) {
            CLRQueueCapture(s->queue,list,dest,2); break;
        }
    }
    return noErr;
}
static OSStatus find(MIDIDriverRef s, MIDIDeviceListRef d) { return noErr; }
static OSStatus configure(MIDIDriverRef s, MIDIDeviceRef d) { return noErr; }
static OSStatus sendOld(MIDIDriverRef s,const MIDIPacketList *p,void *a,void *b) { return noErr; }
static OSStatus enable(MIDIDriverRef s,MIDIEndpointRef e,Boolean b) { return noErr; }
static OSStatus flush(MIDIDriverRef s,MIDIEndpointRef e,void *a,void *b) { return noErr; }
static OSStatus monitorOld(MIDIDriverRef s,MIDIEndpointRef e,const MIDIPacketList *p) { return noErr; }
static OSStatus sendNew(MIDIDriverRef s,const MIDIEventList *p,void *a,void *b) { return noErr; }
static MIDIDriverInterface interface = {NULL,query,addRef,release,find,start,stop,configure,sendOld,enable,flush,monitorOld,sendNew,monitor};
__attribute__((visibility("default"))) void *CLRSpyFactory(CFAllocatorRef allocator, CFUUIDRef type) {
    if (!CFEqual(type,kMIDIDriverTypeID)) return NULL;
    Spy *s = calloc(1,sizeof(Spy)); if (!s) return NULL;
    s->interface=&interface; s->refs=1; s->queue=CLRQueueCreate(512);
    if (!s->queue) { free(s); return NULL; }
    mach_timebase_info_data_t timebase; mach_timebase_info(&timebase);
    s->leaseTicks=(uint64_t)(LEASE_SECONDS*1000000000.0*timebase.denom/timebase.numer);
    atomic_init(&s->deadline,0); atomic_init(&s->stopping,false); atomic_init(&s->monitorStatus,0);
    pthread_mutex_init(&s->startupLock,NULL); pthread_cond_init(&s->startupCondition,NULL);
    for(int i=0;i<MAX_DEST;i++) atomic_init(&s->destinations[i],0);
    return s;
}
