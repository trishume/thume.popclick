#include "detectors.h"

#include <iostream>
#include <numeric>
#include <algorithm>
#include <cmath>

using namespace std;

static const bool kDelayMatch = false;

static const int kDebugHeight = 9;
static const int kPreferredBlockSize = 512;
static const int kSpectrumSize = kPreferredBlockSize/2+1;

static const size_t kMainBandLow = 40;
static const size_t kMainBandHi = 100;
static const size_t kOptionalBandHi = 180;

static const size_t kLowerBandLow = 3;
static const size_t kLowerBandHi = kMainBandLow;
static const size_t kOptionalBandLo = kMainBandHi;
static const size_t kUpperBandLo = kOptionalBandHi;
static const size_t kUpperBandHi = kSpectrumSize;

static const float kDefaultLowPassWeight = 0.6;
static const int kSpeechShadowTime = 100;
static const float kSpeechThresh = 0.5;

Detectors::Detectors(float inputSampleRate) {
    m_blockSize = kPreferredBlockSize;
    m_sensitivity = 5.0;
    m_hysterisisFactor = 0.4;
    m_maxShiftDown = 4;
    m_maxShiftUp = 2;
    m_minFrames = 20;
    m_minFramesLong = 100;
    m_lowPassWeight = kDefaultLowPassWeight;
}

size_t Detectors::getPreferredBlockSize() const {
    return m_blockSize;
}

size_t Detectors::getPreferredStepSize() const {
    return m_blockSize/4;
}

bool Detectors::initialise(size_t channels, size_t, size_t blockSize) {
    // Real initialisation work goes here!
    m_blockSize = blockSize;
    m_savedOtherBands = 0.0002;
    m_consecutiveMatches = 0;
    m_framesSinceSpeech = 1000;
    m_framesSinceMatch = 1000;
    lowPassBuffer.resize(m_blockSize / 2 + 1, 0.0);
    return true;
}

int Detectors::process(const float *const *inputBuffers) {
    int result = 0;
    if (m_blockSize == 0) {
        cerr << "ERROR: Detectors::process: Not initialised" << endl;
        return result;
    }

    size_t n = m_blockSize / 2 + 1;
    const float *fbuf = inputBuffers[0];

    for (size_t i = 0; i < n; ++i) {
        double real = fbuf[i * 2];
        double imag = fbuf[i * 2 + 1];
        double newVal = real * real + imag * imag;
        lowPassBuffer[i] = lowPassBuffer[i]*(1.0-m_lowPassWeight) + newVal*m_lowPassWeight;
    }

    float lowerBand = avgBand(lowPassBuffer, kLowerBandLow, kLowerBandHi);
    float mainBand = avgBand(lowPassBuffer, kMainBandLow, kMainBandHi);
    float optionalBand = avgBand(lowPassBuffer, kOptionalBandLo, kOptionalBandHi);
    float upperBand = avgBand(lowPassBuffer, kUpperBandLo, kUpperBandHi);

    // TODO: integer overflow if no speech for a long time
    m_framesSinceSpeech += 1;
    if(lowerBand > kSpeechThresh) {
        m_framesSinceSpeech = 0;
    }

    float debugMarker = 0.0002;
    float matchiness = mainBand / ((lowerBand+upperBand)/2.0);
    bool outOfShadow = m_framesSinceSpeech > kSpeechShadowTime;
    bool optionalPresent = (optionalBand > upperBand*5 || matchiness >= m_sensitivity*2);
    int immediateMatchFrame = kDelayMatch ? m_minFramesLong : m_minFrames;
    m_framesSinceMatch += 1;
    if(((matchiness >= m_sensitivity) ||
        (m_consecutiveMatches > 0 && matchiness >= m_sensitivity*m_hysterisisFactor) ||
        (m_consecutiveMatches > immediateMatchFrame && (mainBand/m_savedOtherBands) >= m_sensitivity*m_hysterisisFactor*0.5))
     && outOfShadow) {
        debugMarker = 0.01;
        // second one in double "tss" came earlier than trigger timer
        if(kDelayMatch && m_consecutiveMatches == 0 && m_framesSinceMatch <= m_minFramesLong) {
            result |= 1;
            result |= 2;
            m_framesSinceMatch = 1000;
        }

        m_consecutiveMatches += 1;
        if(kDelayMatch && m_consecutiveMatches == m_minFrames) {
            m_framesSinceMatch = m_consecutiveMatches;
        } else if(m_consecutiveMatches == immediateMatchFrame) {
            debugMarker = 1.0;
            result |= 1;
            m_savedOtherBands = ((lowerBand+upperBand)/2.0);
        }
    } else {
        bool delayedMatch = kDelayMatch && (m_framesSinceMatch == m_minFramesLong && outOfShadow);
        if(delayedMatch) {
            result |= 1;
        }
        if(m_consecutiveMatches >= immediateMatchFrame || delayedMatch) {
            debugMarker = 2.0;
            result |= 2;
        }
        m_consecutiveMatches = 0;
    }

    return result;
}

float Detectors::avgBand(std::vector<float> &frame, size_t low, size_t hi) {
    float sum = 0;
    for (size_t i = low; i < hi; ++i) {
        sum += frame[i];
    }
    return sum / (hi - low);
}

