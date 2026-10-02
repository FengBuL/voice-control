#include "AudioDSP.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    float samples[] = {0.8f, -0.4f, 0.2f, -1.0f};
    float result[] = {9, 9, 9, 9};
    AudioBufferList input = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(samples), samples}}};
    AudioBufferList output = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(result), result}}};
    void *context = SVAudioCreate(0.25, 48000);
    assert(context);
    SVAudioProcess(context, &input, &output);
    assert(fabsf(result[0] - 0.2f) < 0.00001f);
    assert(fabsf(result[1] + 0.1f) < 0.00001f);
    assert(fabsf(result[2] - 0.05f) < 0.00001f);
    assert(fabsf(result[3] + 0.25f) < 0.00001f);
    assert(SVAudioFrames(context) == 2 && SVAudioSignalFrames(context) == 2);
    SVAudioProcess(context, NULL, &output);
    for (int i = 0; i < 4; i++) assert(result[i] == 0);
    SVAudioDestroy(context);

    float left[] = {0.8f, 0.2f}, right[] = {-0.4f, -1.0f};
    struct { UInt32 count; AudioBuffer buffers[2]; } separate = {
        2, {{1, sizeof(left), left}, {1, sizeof(right), right}}
    };
    context = SVAudioCreate(0.5, 48000);
    SVAudioProcess(context, (AudioBufferList *)&separate, &output);
    assert(fabsf(result[0] - 0.4f) < 0.00001f && fabsf(result[1] + 0.2f) < 0.00001f);
    assert(fabsf(result[2] - 0.1f) < 0.00001f && fabsf(result[3] + 0.5f) < 0.00001f);
    SVAudioDestroy(context);

    float longInput[2048], longOutput[2048];
    for (int i = 0; i < 2048; i++) longInput[i] = 0.5f;
    input.mBuffers[0] = (AudioBuffer){2, sizeof(longInput), longInput};
    output.mBuffers[0] = (AudioBuffer){2, sizeof(longOutput), longOutput};
    context = SVAudioCreate(1, 48000);
    SVAudioSetGain(context, 0);
    SVAudioProcess(context, &input, &output);
    assert(longOutput[0] > 0 && longOutput[2047] == 0);
    SVAudioSetGain(context, 5); // Gain must never amplify above unity.
    SVAudioProcess(context, &input, &output);
    assert(fabsf(longOutput[2047] - 0.5f) < 0.00001f);
    SVAudioDestroy(context);
    puts("Audio DSP checks passed: stereo attenuation, planar input, silence, smooth mute and gain limits.");
}
