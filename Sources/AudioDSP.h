#pragma once
#include <CoreAudio/AudioHardware.h>
#include <stdint.h>

void * _Nullable SVAudioCreate(float gain, double sampleRate);
void SVAudioDestroy(void * _Nullable context);
void SVAudioSetGain(void * _Nullable context, float gain);
void SVAudioProcess(void * _Nullable context, const AudioBufferList * _Nullable input, AudioBufferList * _Nullable output);
uint64_t SVAudioFrames(void * _Nullable context);
uint64_t SVAudioSignalFrames(void * _Nullable context);
OSStatus SVAudioIOProc(AudioObjectID device, const AudioTimeStamp * _Nonnull now,
                      const AudioBufferList * _Nonnull input, const AudioTimeStamp * _Nonnull inputTime,
                      AudioBufferList * _Nonnull output, const AudioTimeStamp * _Nonnull outputTime,
                      void * _Nullable context);
