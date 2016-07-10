#include "detectors.h"

#include <iostream>
#include <numeric>
#include <algorithm>
#include <cmath>

using namespace std;

static const bool kDelayMatch = false;

static const int kDebugHeight = 9;
static const int kBlockSize = 512;
static const int kLogBlockSize = 9;
static const int kSpectrumSize = kBlockSize/2;
static const int kWindowSize = kBlockSize;

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

Detectors::Detectors() {
    m_sensitivity = 5.0;
    m_hysterisisFactor = 0.4;
    m_maxShiftDown = 4;
    m_maxShiftUp = 2;
    m_minFrames = 20;
    m_minFramesLong = 100;
    m_lowPassWeight = kDefaultLowPassWeight;

    m_inReal = (float *) malloc(kBlockSize * sizeof(float));
    m_outReal = (float *) malloc(kBlockSize * sizeof(float));
    m_splitData.realp = (float *) malloc(kSpectrumSize * sizeof(float));
    m_splitData.imagp = (float *) malloc(kSpectrumSize * sizeof(float));

    m_window = (float *) malloc(sizeof(float) * kWindowSize);
    memset(m_window, 0, sizeof(float) * kWindowSize);
    vDSP_hann_window(m_window, kWindowSize, vDSP_HANN_NORM);

    m_fftSetup = vDSP_create_fftsetup(kLogBlockSize, FFT_RADIX2);
}

Detectors::~Detectors() {
    free(m_inReal);
    free(m_outReal);
    free(m_splitData.realp);
    free(m_splitData.imagp);
    free(m_window);

    vDSP_destroy_fftsetup(m_fftSetup);
}

size_t Detectors::getPreferredBlockSize() const {
    return kBlockSize;
}

size_t Detectors::getPreferredStepSize() const {
    return kBlockSize/4;
}

bool Detectors::initialise() {
    // Real initialisation work goes here!
    m_savedOtherBands = 0.0002;
    m_consecutiveMatches = 0;
    m_framesSinceSpeech = 1000;
    m_framesSinceMatch = 1000;
    lowPassBuffer.resize(kBlockSize / 2, 0.0);
    return true;
}

void Detectors::doFFT(float *buffer) {
    vDSP_vmul(buffer, 1, m_window, 1, m_inReal, 1, kBlockSize);
    vDSP_ctoz((DSPComplex *) m_inReal, 2, &m_splitData, 1, kSpectrumSize);
    vDSP_fft_zrip(m_fftSetup, &m_splitData, 1, kLogBlockSize, FFT_FORWARD);
    m_splitData.imagp[0] = 0.0;

    float scale = (float) 1.0 / (2 * (float)kBlockSize);
    vDSP_vsmul(m_splitData.realp, 1, &scale, m_splitData.realp, 1, kSpectrumSize);
    vDSP_vsmul(m_splitData.imagp, 1, &scale, m_splitData.imagp, 1, kSpectrumSize);
}

int Detectors::process(float *buffer) {
    int result = 0;

    doFFT(buffer);

    size_t n = kSpectrumSize;

    float scale = (float) 1.0 / (2 * (float)kBlockSize);
    for (size_t i = 0; i < n; ++i) {
        double real = m_splitData.realp[i];
        double imag = m_splitData.imagp[i];
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

