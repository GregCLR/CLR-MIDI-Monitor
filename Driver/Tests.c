// Runs driver code in this process only. Never creates a MIDI client or registers
// with MIDIServer. The sole monitoring-registration call is replaced by a stub.
#include <CoreMIDI/MIDIDriver.h>
#include <assert.h>
#include <stdio.h>
#include <pthread.h>
static int enableCalls=0;
static OSStatus testEnable(MIDIDriverRef self, Boolean enabled) { enableCalls += enabled ? 1 : -1; return noErr; }
#define CLR_SPY_PORT_FORMAT "com.clr.midimonitor.spy.test.v1.%u"
#define MIDIDriverEnableMonitoring testEnable
#include "CLRSpy.c"
#undef MIDIDriverEnableMonitoring
static MIDIEventList list;
static CFDataRef message(CFMessagePortRef remote, uint64_t token, uint32_t destination, int command) {
    uint8_t bytes[16]; uint32_t count=destination?1:0;
    memcpy(bytes,&token,8); memcpy(bytes+8,&count,4); memcpy(bytes+12,&destination,4);
    CFDataRef data=CFDataCreate(NULL,bytes,12+count*4), reply=NULL;
    SInt32 result=CFMessagePortSendRequest(remote,command,data,1,1,kCFRunLoopDefaultMode,&reply);
    CFRelease(data); assert(result==kCFMessagePortSuccess && reply); return reply;
}
static uint32_t value(CFDataRef data,int offset) { uint32_t v; memcpy(&v,CFDataGetBytePtr(data)+offset,4); return v; }
static void *produce(void *context) {
    for(int i=0;i<10000;i++) monitor((MIDIDriverRef)context,42,&list);
    return NULL;
}
int main(int argc, char **argv) {
    Spy *s=CLRSpyFactory(NULL,kMIDIDriverTypeID); assert(s);
    MIDIEventPacket *packet=MIDIEventListInit(&list,kMIDIProtocol_1_0);
    uint32_t words[]={0x20903C64,0x20B04A60,0x20803C00};
    assert(MIDIEventListAdd(&list,sizeof(list),packet,123,3,words));
    MIDIEventList before=list;
    assert(start((MIDIDriverRef)s,0)==0 && enableCalls==1);
    CFStringRef name=CFStringCreateWithFormat(NULL,NULL,CFSTR(CLR_SPY_PORT_FORMAT),getuid());
    CFMessagePortRef remote=CFMessagePortCreateRemote(NULL,name); CFRelease(name); assert(remote);
    if (argc > 1 && strcmp(argv[1],"--serve")==0) {
        puts("Isolated driver host ready; no CoreMIDI client or real MIDI sends."); fflush(stdout);
        for (int i=0;i<200;i++) { monitor((MIDIDriverRef)s,42,&list); usleep(10000); }
        CFRelease(remote); release(s); return 0;
    }
    // No client lease: absolutely no capture.
    monitor((MIDIDriverRef)s,42,&list);
    CFDataRef reply=message(remote,111,42,1); assert(value(reply,4)==0 && value(reply,16)==0); CFRelease(reply);
    monitor((MIDIDriverRef)s,99,&list); // deselected destination
    monitor((MIDIDriverRef)s,42,&list);
    reply=message(remote,111,42,1); assert(value(reply,16)==1 && value(reply,20)==42);
    assert(CFDataGetLength(reply)==56); assert(value(reply,44)==0x20903C64); CFRelease(reply);
    assert(memcmp(&list,&before,sizeof(list))==0); // callback never modifies original traffic
    reply=message(remote,222,42,1); assert(value(reply,4)==2); CFRelease(reply); // exclusive reader
    pthread_t threads[4];
    for(int i=0;i<4;i++) assert(pthread_create(&threads[i],NULL,produce,s)==0);
    for(int i=0;i<4;i++) pthread_join(threads[i],NULL);
    reply=message(remote,111,42,1);
    uint64_t drops; memcpy(&drops,CFDataGetBytePtr(reply)+8,8);
    assert(drops>0 && value(reply,16)<=64); CFRelease(reply);
    // Stop and lease expiry both stop accepting new packets.
    reply=message(remote,111,0,2); CFRelease(reply);
    CLRPacketRecord record; while(CLRQueuePop(s->queue,&record)) {}
    monitor((MIDIDriverRef)s,42,&list); assert(!CLRQueuePop(s->queue,&record));
    reply=message(remote,222,42,1); assert(value(reply,4)==0); CFRelease(reply);
    atomic_store(&s->deadline,mach_absolute_time()-1);
    monitor((MIDIDriverRef)s,42,&list); assert(!CLRQueuePop(s->queue,&record));
    // Oversize packet is dropped rather than overflowing the bounded buffer.
    uint32_t big[4097]={0}; assert(!CLRQueuePush(s->queue,42,2,0,0,big,4097));
    assert(CLRQueueTakeDrops(s->queue).oversized==1);
    CFRelease(remote);
    assert(stop((MIDIDriverRef)s)==0 && enableCalls==0);
    assert(start((MIDIDriverRef)s,0)==0 && enableCalls==1);
    stop((MIDIDriverRef)s); assert(enableCalls==0);
    // release calls idempotent Stop; the stub tolerates redundant disable.
    release(s);
    puts("PASS: isolated driver IPC, exact packet preservation, selection, exclusive lease, four-producer overload, oversize handling, stop/restart and expiry. No MIDI server connection or transmission.");
}
