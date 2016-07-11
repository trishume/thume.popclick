#include "detectors.h"

#include <iostream>
#include <numeric>
#include <algorithm>
#include <cmath>

using namespace std;

#include "poptemplate.h"

static const bool kDelayMatch = false;

static const int kDebugHeight = 9;
static const int kBlockSize = 512;
static const int kLogBlockSize = 9;
static const int kSpectrumSize = kBlockSize/2;
static const int kWindowSize = kBlockSize;

static const int kNumSteps = 4;
static const int kStepSize = kBlockSize / kNumSteps;

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
    overlapBuffer = (float *) malloc(kBlockSize * 2 * sizeof(float));

    // === Tss Detection
    m_sensitivity = 5.0;
    m_hysterisisFactor = 0.4;
    m_minFrames = 20;
    m_minFramesLong = 100;
    m_lowPassWeight = kDefaultLowPassWeight;

    // === Pop detection
    m_startBin = 2;
    m_maxShiftDown = 4;
    m_maxShiftUp = 2;
    m_popSensitivity = 8.5;
    m_framesSincePop = 0;

    // debugLog = new std::ofstream("/Users/tristan/misc/popclick.log");

    // === FFT
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
    free(overlapBuffer);

    free(m_inReal);
    free(m_outReal);
    free(m_splitData.realp);
    free(m_splitData.imagp);
    free(m_window);
    // delete debugLog;

    vDSP_destroy_fftsetup(m_fftSetup);
}

size_t Detectors::getPreferredBlockSize() const {
    return kBlockSize;
}

bool Detectors::initialise() {
    // Real initialisation work goes here!
    m_savedOtherBands = 0.0002;
    m_consecutiveMatches = 0;
    m_framesSinceSpeech = 1000;
    m_framesSinceMatch = 1000;
    lowPassBuffer.resize(kSpectrumSize, 0.0);

    spectrum.resize(kSpectrumSize, 0.0);
    m_popBuffer.clear();
    for(unsigned i = 0; i < kBufferSize; ++i) {
        m_popBuffer.push_back(0.0);
    }

    return true;
}

int Detectors::process(float *buffer) {
    // return processChunk(buffer);
    // copy last frame to start of the buffer
    std::copy(overlapBuffer+kBlockSize, overlapBuffer+(kBlockSize*2), overlapBuffer);
    // copy new input to the second half of the overlap buffer
    std::copy(buffer,buffer+kBlockSize,overlapBuffer+kBlockSize);

    int result = 0;
    for(int i = 0; i < kNumSteps; ++i) {
        float *ptr = overlapBuffer+((i+1)*kStepSize);
        result |= processChunk(ptr);
    }
    return result;
}

void Detectors::doFFT(const float *buffer) {
    vDSP_vmul(buffer, 1, m_window, 1, m_inReal, 1, kBlockSize);
    vDSP_ctoz((DSPComplex *) m_inReal, 2, &m_splitData, 1, kSpectrumSize);
    vDSP_fft_zrip(m_fftSetup, &m_splitData, 1, kLogBlockSize, FFT_FORWARD);
    m_splitData.imagp[0] = 0.0;

    float scale = (float) 1.0 / (2 * (float)kBlockSize);
    vDSP_vsmul(m_splitData.realp, 1, &scale, m_splitData.realp, 1, kSpectrumSize);
    vDSP_vsmul(m_splitData.imagp, 1, &scale, m_splitData.imagp, 1, kSpectrumSize);
}

int Detectors::processChunk(const float *buffer) {
    doFFT(buffer);

    int result = 0;
    size_t n = kSpectrumSize;

    float scale = (float) 1.0 / (2 * (float)kBlockSize);
    for (size_t i = 0; i < n; ++i) {
        double real = m_splitData.realp[i];
        double imag = m_splitData.imagp[i];
        double newVal = real * real + imag * imag;
        spectrum[i] = newVal;
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

    // ===================== Pop Detection =================================
    // update buffer forward one time step
    for(unsigned i = 0; i < kBufferPrimaryHeight; ++i) {
        m_popBuffer.pop_front();
        m_popBuffer.push_back(spectrum[i]);
    }
    // high frequencies aren't useful so we bin them all together
    m_popBuffer.pop_front();
    float highSum = accumulate(spectrum.begin()+kBufferPrimaryHeight,spectrum.end(),0.0);
    m_popBuffer.push_back(highSum);

    auto maxIt = max_element(m_popBuffer.begin(), m_popBuffer.end());
    float minDiff = 10000000.0;
    for(int i = -m_maxShiftUp; i < m_maxShiftDown; ++i) {
        float diff = templateDiff(*maxIt, i);
        if(diff < minDiff) minDiff = diff;
    }

    m_framesSincePop += 1;
    if(minDiff < m_popSensitivity && m_framesSincePop > 15) {
        result |= 4; // Detected pop
        m_framesSincePop = 0;
    }

    // *debugLog << lowerBand << ' ' << mainBand << ' ' << optionalBand << ' ' << upperBand << '-' << matchiness << ' ' << debugMarker << std::endl;
    return result;
}

float Detectors::avgBand(std::vector<float> &frame, size_t low, size_t hi) {
    float sum = 0;
    for (size_t i = low; i < hi; ++i) {
        sum += frame[i];
    }
    return sum / (hi - low);
}

float Detectors::templateAt(int i, int shift) {
    int bin = i % kBufferHeight;
    if(i % kBufferHeight >= kBufferPrimaryHeight) {
        return kPopTemplate[i]/kPopTemplateMax;
    }
    if(bin+shift < 0 || bin+shift >= kBufferPrimaryHeight) {
        return 0.0;
    }
    return kPopTemplate[i+shift]/kPopTemplateMax;
}

float Detectors::diffCol(int templStart, int bufStart, float maxVal, int shift) {
    float diff = 0;
    for(unsigned i = m_startBin; i < kBufferHeight; ++i) {
        float d = templateAt(templStart+i, shift) - m_popBuffer[bufStart+i]/maxVal;
        diff += abs(d);
    }
    return diff;
}

float Detectors::templateDiff(float maxVal, int shift) {
    float diff = 0;
    for(unsigned i = 0; i < kBufferSize; i += kBufferHeight) {
        diff += diffCol(i,i, maxVal,shift);
    }
    return diff;
}

