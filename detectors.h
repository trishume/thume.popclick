#ifndef _TSSDETECTOR_H_
#define _TSSDETECTOR_H_

#include <vector>

#include <Accelerate/Accelerate.h>

using std::string;

class Detectors {
public:
    Detectors(float inputSampleRate);
    ~Detectors();

    size_t getPreferredBlockSize() const;
    size_t getPreferredStepSize() const;

    bool initialise();

    int process(float *buffer);

protected:
    void doFFT(float *buffer);
    // plugin-specific data and methods go here
    float m_sensitivity;
    float m_hysterisisFactor;
    float m_lowPassWeight;
    int m_minFrames;
    int m_minFramesLong;
    int m_maxShiftDown;
    int m_maxShiftUp;

    std::vector<float> lowPassBuffer;
    int m_consecutiveMatches;
    int m_framesSinceSpeech;
    int m_framesSinceMatch;
    float m_savedOtherBands;

    float *m_inReal;
    float *m_outReal;
    float *m_window;
    FFTSetup m_fftSetup;
    DSPSplitComplex m_splitData;

    float avgBand(std::vector<float> &frame, size_t low, size_t hi);
};



#endif
