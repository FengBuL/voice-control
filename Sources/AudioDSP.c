#include "AudioDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// The callback performs no allocation, locking, file I/O or Swift work.
typedef struct {
    _Atomic(float) target;
    float current, step;
    atomic_uint_fast64_t frames, signalFrames;
} AudioContext;

static float bounded(float gain) {
    return isfinite(gain) ? fminf(1, fmaxf(0, gain)) : 0;
}

void *SVAudioCreate(float gain, double rate) {
    AudioContext *ctx = calloc(1, sizeof(AudioContext));
    if (!ctx) return NULL;
    atomic_init(&ctx->target, bounded(gain));
    ctx->current = bounded(gain);
    ctx->step = 1.0f / fmaxf(1, (float)rate * 0.01f);
    atomic_init(&ctx->frames, 0);
    atomic_init(&ctx->signalFrames, 0);
    return ctx;
}
void SVAudioDestroy(void *context) { free(context); }
void SVAudioSetGain(void *context, float gain) {
    if (context) atomic_store_explicit(&((AudioContext *)context)->target, bounded(gain), memory_order_relaxed);
}
uint64_t SVAudioFrames(void *context) {
    return context ? atomic_load_explicit(&((AudioContext *)context)->frames, memory_order_relaxed) : 0;
}
uint64_t SVAudioSignalFrames(void *context) {
    return context ? atomic_load_explicit(&((AudioContext *)context)->signalFrames, memory_order_relaxed) : 0;
}

static float sample(const AudioBufferList *list, UInt32 frame, UInt32 channel) {
    UInt32 first = 0;
    for (UInt32 i = 0; i < list->mNumberBuffers; i++) {
        const AudioBuffer *b = &list->mBuffers[i];
        if (channel >= first && channel < first + b->mNumberChannels) {
            UInt32 offset = frame * b->mNumberChannels + channel - first;
            if (!b->mData || offset >= b->mDataByteSize / sizeof(float)) return 0;
            float value = ((const float *)b->mData)[offset];
            return isfinite(value) ? value : 0;
        }
        first += b->mNumberChannels;
    }
    return 0;
}

void SVAudioProcess(void *context, const AudioBufferList *input, AudioBufferList *output) {
    if (!output) return;
    for (UInt32 i = 0; i < output->mNumberBuffers; i++) {
        if (output->mBuffers[i].mData) memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    }
    if (!context || !input || !input->mNumberBuffers || !output->mNumberBuffers) return;
    AudioContext *ctx = context;
    UInt32 frames = UINT32_MAX;
    for (UInt32 i = 0; i < output->mNumberBuffers; i++) {
        const AudioBuffer *b = &output->mBuffers[i];
        if (!b->mNumberChannels || !b->mData) return;
        UInt32 available = b->mDataByteSize / (sizeof(float) * b->mNumberChannels);
        if (available < frames) frames = available;
    }
    uint64_t active = 0;
    float target = atomic_load_explicit(&ctx->target, memory_order_relaxed);
    for (UInt32 frame = 0; frame < frames; frame++) {
        float difference = target - ctx->current;
        ctx->current += fminf(ctx->step, fmaxf(-ctx->step, difference));
        UInt32 channel = 0;
        int hasSignal = 0;
        for (UInt32 i = 0; i < output->mNumberBuffers; i++) {
            AudioBuffer *out = &output->mBuffers[i];
            float *data = out->mData;
            for (UInt32 c = 0; c < out->mNumberChannels; c++, channel++) {
                float value = sample(input, frame, channel);
                if (fabsf(value) > 0.000001f) hasSignal = 1;
                data[frame * out->mNumberChannels + c] = value * ctx->current;
            }
        }
        active += hasSignal;
    }
    atomic_fetch_add_explicit(&ctx->frames, frames, memory_order_relaxed);
    atomic_fetch_add_explicit(&ctx->signalFrames, active, memory_order_relaxed);
}

OSStatus SVAudioIOProc(AudioObjectID device, const AudioTimeStamp *now,
                       const AudioBufferList *input, const AudioTimeStamp *inputTime,
                       AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    SVAudioProcess(context, input, output);
    return 0;
}
