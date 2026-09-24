#include "CaptureTransport.h"
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "64-bit counters must be lock free");
struct CLRPacketQueue {
    atomic_flag busy;
    _Atomic unsigned long long full, contention, oversized;
    uint32_t capacity, readIndex, writeIndex, count;
    CLRPacketRecord records[];
};

CLRPacketQueue *CLRQueueCreate(uint32_t capacity) {
    if (capacity == 0 || capacity > 4096) return NULL;
    CLRPacketQueue *q = calloc(1, sizeof(*q) + capacity * sizeof(CLRPacketRecord));
    if (!q) return NULL;
    atomic_flag_clear(&q->busy);
    atomic_init(&q->full, 0); atomic_init(&q->contention, 0); atomic_init(&q->oversized, 0);
    q->capacity = capacity;
    // Touch storage off the callback thread rather than defer first writes.
    for (uint32_t i = 0; i < capacity; ++i) q->records[i].words[0] = 0;
    return q;
}
void CLRQueueDestroy(CLRPacketQueue *q) { free(q); }
bool CLRQueuePush(CLRPacketQueue *q, uint32_t endpoint, uint8_t path,
                  uint64_t timestamp, uint64_t receivedAt,
                  const uint32_t *words, uint32_t wordCount) {
    if (wordCount > CLR_MAX_PACKET_WORDS) {
        atomic_fetch_add_explicit(&q->oversized, 1, memory_order_relaxed); return false;
    }
    if (atomic_flag_test_and_set_explicit(&q->busy, memory_order_acquire)) {
        atomic_fetch_add_explicit(&q->contention, 1, memory_order_relaxed); return false;
    }
    if (q->count == q->capacity) {
        atomic_flag_clear_explicit(&q->busy, memory_order_release);
        atomic_fetch_add_explicit(&q->full, 1, memory_order_relaxed); return false;
    }
    CLRPacketRecord *record = &q->records[q->writeIndex];
    record->endpoint = endpoint; record->path = path;
    record->timestamp = timestamp; record->receivedAt = receivedAt; record->wordCount = wordCount;
    if (wordCount) memcpy(record->words, words, wordCount * sizeof(uint32_t));
    q->writeIndex = (q->writeIndex + 1) % q->capacity; ++q->count;
    atomic_flag_clear_explicit(&q->busy, memory_order_release);
    return true;
}
void CLRQueueCapture(CLRPacketQueue *q, const MIDIEventList *list, uint32_t endpoint, uint8_t path) {
    const uint64_t arrival = mach_absolute_time();
    const MIDIEventPacket *packet = &list->packet[0];
    for (uint32_t i = 0; i < list->numPackets; ++i) {
        CLRQueuePush(q, endpoint, path, packet->timeStamp, arrival, packet->words, packet->wordCount);
        packet = MIDIEventPacketNext(packet);
    }
}
bool CLRQueuePop(CLRPacketQueue *q, CLRPacketRecord *record) {
    if (atomic_flag_test_and_set_explicit(&q->busy, memory_order_acquire)) return false;
    if (q->count == 0) { atomic_flag_clear_explicit(&q->busy, memory_order_release); return false; }
    const CLRPacketRecord *source = &q->records[q->readIndex];
    record->endpoint = source->endpoint; record->path = source->path;
    record->timestamp = source->timestamp; record->receivedAt = source->receivedAt; record->wordCount = source->wordCount;
    if (source->wordCount) memcpy(record->words, source->words, source->wordCount * sizeof(uint32_t));
    q->readIndex = (q->readIndex + 1) % q->capacity; --q->count;
    atomic_flag_clear_explicit(&q->busy, memory_order_release);
    return true;
}
CLRDropCounts CLRQueueTakeDrops(CLRPacketQueue *q) {
    return (CLRDropCounts){atomic_exchange_explicit(&q->full, 0, memory_order_relaxed),
                          atomic_exchange_explicit(&q->contention, 0, memory_order_relaxed),
                          atomic_exchange_explicit(&q->oversized, 0, memory_order_relaxed)};
}
