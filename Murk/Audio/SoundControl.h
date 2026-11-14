#ifndef MurkSoundControl_h
#define MurkSoundControl_h

#include <stdint.h>

/// Lock-free control values shared between the UI thread and the real-time audio thread.
/// Every field is a C atomic, so neither side ever waits on the other.
typedef struct MurkSoundControl MurkSoundControl;

MurkSoundControl *MurkSoundControlCreate(void);

// UI thread → audio thread
void MurkSoundControlSetTargets(MurkSoundControl *c, float rain, float wind);
void MurkSoundControlTriggerThunder(MurkSoundControl *c, float strength);
void MurkSoundControlSetSampleRate(MurkSoundControl *c, float rate);

// Read on the audio thread
float MurkSoundControlRain(const MurkSoundControl *c);
float MurkSoundControlWind(const MurkSoundControl *c);
float MurkSoundControlSampleRate(const MurkSoundControl *c);
uint32_t MurkSoundControlThunderSerial(const MurkSoundControl *c);
float MurkSoundControlThunderStrength(const MurkSoundControl *c);

// Audio thread → UI thread: how loud the thunder still is, so the UI knows when it can pause.
void MurkSoundControlPublishThunderLevel(MurkSoundControl *c, float level);
float MurkSoundControlThunderLevel(const MurkSoundControl *c);

#endif
