#pragma once
#include <CoreMIDI/CoreMIDI.h>
#include <stdbool.h>
#include <stdint.h>

// Fixed memory budget: 4096 words/record (16 KiB), capacity chosen at creation.
// Larger legal CoreMIDI packets are explicitly dropped, never truncated.
#define CLR_MAX_PACKET_WORDS 4096
typedef struct CLRPacketQueue CLRPacketQueue;
typedef struct {
    uint64_t timestamp;
    uint64_t receivedAt;
    uint32_t endpoint;
    uint32_t wordCount;
    uint8_t path;
    uint32_t words[CLR_MAX_PACKET_WORDS];
} CLRPacketRecord;
typedef struct {
    uint64_t full;
    uint64_t contention;
    uint64_t oversized;
} CLRDropCounts;

CLRPacketQueue *CLRQueueCreate(uint32_t capacity);
// Caller must stop/join producers and consumers before destroying.
void CLRQueueDestroy(CLRPacketQueue *queue);
// No allocation, blocking lock, spin loop, decoding or I/O in push/capture.
bool CLRQueuePush(CLRPacketQueue *queue, uint32_t endpoint, uint8_t path,
                  uint64_t timestamp, uint64_t receivedAt,
                  const uint32_t *words, uint32_t wordCount);
void CLRQueueCapture(CLRPacketQueue *queue, const MIDIEventList *list,
                     uint32_t endpoint, uint8_t path);
bool CLRQueuePop(CLRPacketQueue *queue, CLRPacketRecord *record);
CLRDropCounts CLRQueueTakeDrops(CLRPacketQueue *queue);
