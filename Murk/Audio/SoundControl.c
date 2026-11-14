#include "SoundControl.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct MurkSoundControl {
    _Atomic uint32_t rain;
    _Atomic uint32_t wind;
    _Atomic uint32_t sampleRate;
    _Atomic uint32_t thunderSerial;
    _Atomic uint32_t thunderStrength;
    _Atomic uint32_t thunderLevel;
};

static inline uint32_t bits(float f) { uint32_t u; memcpy(&u, &f, sizeof u); return u; }
static inline float value(uint32_t u) { float f; memcpy(&f, &u, sizeof f); return f; }

MurkSoundControl *MurkSoundControlCreate(void) {
    MurkSoundControl *c = calloc(1, sizeof(MurkSoundControl));
    atomic_init(&c->rain, bits(0));
    atomic_init(&c->wind, bits(0));
    atomic_init(&c->sampleRate, bits(48000));
    atomic_init(&c->thunderSerial, 0);
    atomic_init(&c->thunderStrength, bits(0));
    atomic_init(&c->thunderLevel, bits(0));
    return c;
}

void MurkSoundControlSetTargets(MurkSoundControl *c, float rain, float wind) {
    atomic_store_explicit(&c->rain, bits(rain), memory_order_relaxed);
    atomic_store_explicit(&c->wind, bits(wind), memory_order_relaxed);
}

void MurkSoundControlTriggerThunder(MurkSoundControl *c, float strength) {
    // Strength first, then the serial: the audio thread reads the strength only after it sees a new serial.
    atomic_store_explicit(&c->thunderStrength, bits(strength), memory_order_release);
    atomic_store_explicit(&c->thunderLevel, bits(1), memory_order_relaxed);
    atomic_fetch_add_explicit(&c->thunderSerial, 1, memory_order_release);
}

void MurkSoundControlSetSampleRate(MurkSoundControl *c, float rate) {
    atomic_store_explicit(&c->sampleRate, bits(rate), memory_order_relaxed);
}

float MurkSoundControlRain(const MurkSoundControl *c) { return value(atomic_load_explicit(&c->rain, memory_order_relaxed)); }
float MurkSoundControlWind(const MurkSoundControl *c) { return value(atomic_load_explicit(&c->wind, memory_order_relaxed)); }
float MurkSoundControlSampleRate(const MurkSoundControl *c) { return value(atomic_load_explicit(&c->sampleRate, memory_order_relaxed)); }
uint32_t MurkSoundControlThunderSerial(const MurkSoundControl *c) { return atomic_load_explicit(&c->thunderSerial, memory_order_acquire); }
float MurkSoundControlThunderStrength(const MurkSoundControl *c) { return value(atomic_load_explicit(&c->thunderStrength, memory_order_acquire)); }

void MurkSoundControlPublishThunderLevel(MurkSoundControl *c, float level) {
    atomic_store_explicit(&c->thunderLevel, bits(level), memory_order_relaxed);
}
float MurkSoundControlThunderLevel(const MurkSoundControl *c) { return value(atomic_load_explicit(&c->thunderLevel, memory_order_relaxed)); }
