# GuitarKit

An iOS toolkit for string players: a multi-instrument tuner at its heart, plus a metronome, a circle of fifths, and chord and scale views that follow the player's current tuning.

## Instruments and tunings

**Instrument**:
A kind of stringed instrument the app knows (6-string guitar, 4-string bass, ukulele, violin…), with its strings, headstock, and preset tunings.
_Avoid_: device, model

**Tuning**:
A named list of open-string notes for an instrument (Standard, Drop D, DADGAD), either a built-in preset or a player-saved custom tuning.
_Avoid_: preset (when a custom tuning is meant too)

**Selection**:
The instrument + tuning the player is currently on. Every tool follows it; only choosing in the Tuner changes it.
_Avoid_: current setup, active instrument

**Reference pitch**:
The frequency of A4 every note is measured against (440 Hz unless the player calibrates, 415–466 Hz).
_Avoid_: A4, calibration, concert pitch (as a setting)

**Capo**:
A fret clamp that raises every open string by the same number of semitones.

**Target**:
The exact frequency one string should sound at, given the tuning, the reference pitch, and the capo.
_Avoid_: goal, expected note

## Tuning a string

**Targeted mode**:
The Tuner's default mode: it knows the tuning's strings and tells the player which string they're on and how far from its target.

**Chromatic mode**:
The mode that names whatever note is sounding, with no tuning assumed.
_Avoid_: free mode, note mode

**Tone mode**:
The mode where tapping a peg plays that string's target instead of listening.
_Avoid_: reference tone mode

**Reading**:
What the Tuner hears at a moment: a pitch, the nearest note, and how many cents off it is — or nothing.
_Avoid_: detection, sample, result

**Tuning session**:
One pass of tuning an instrument: which string is active, how far off it is, and which strings are already latched.

**Zone**:
Where the active string sits relative to its target: flat, sharp, in tune (within the player's tolerance), or perfect (within ±1 cent).

**Hold**:
Staying in tune continuously for a short time (0.7 s); what it takes to latch a string.

**Latch**:
A string confirmed in tune for the rest of the session — it stays green even as the player moves on.
_Avoid_: lock (a lock is the player tapping a peg to choose the string)

**Lock**:
The player tapping a peg to tell the Tuner which string they're tuning, instead of letting it guess.

## Hearing the string

**Pluck**:
A string being struck: a sudden rise in level followed by a steady pitch that fades.
_Avoid_: attack, onset (in user-facing language)

**Interference**:
Any sound in the room that isn't the string being tuned — voices, other instruments, a phone playing video, clicks, fan noise.
_Avoid_: noise (when pitched sounds are meant)

**Detection band**:
The range of pitches the Tuner listens for: around the tuning's strings in targeted mode, everything in chromatic mode.

## Harmony

**Key**:
A tonic plus a major or minor mode, as shown on the circle of fifths.

**Diatonic chord**:
One of the seven chords built on a key's scale degrees.

**Voicing**:
One playable way to finger a chord on the current tuning: which fret (or open/muted) on each string.
_Avoid_: shape, fingering (unless the movable shape itself is meant)
