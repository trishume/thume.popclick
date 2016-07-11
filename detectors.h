#ifndef _TSSDETECTOR_H_
#define _TSSDETECTOR_H_

#include <vector>
// #include <fstream>
#include <deque>

#include <Accelerate/Accelerate.h>

using std::string;

class Detectors {
public:
    Detectors();
    ~Detectors();

    size_t getPreferredBlockSize() const;

    bool initialise();

    int process(float *buffer);

protected:
    int processChunk(const float *buffer);
    void doFFT(const float *buffer);

    // Overlap
    float *overlapBuffer;

    // Tss detection
    float m_sensitivity;
    float m_hysterisisFactor;
    float m_lowPassWeight;
    int m_minFrames;
    int m_minFramesLong;

    std::vector<float> lowPassBuffer;
    int m_consecutiveMatches;
    int m_framesSinceSpeech;
    int m_framesSinceMatch;
    float m_savedOtherBands;

    // Pop detection
    std::vector<float> spectrum;
    std::deque<float> m_popBuffer;
    int m_maxShiftDown;
    int m_maxShiftUp;
    float m_popSensitivity;
    int m_framesSincePop;
    int m_startBin;
    float templateAt(int i, int shift);
    float templateDiff(float maxVal, int shift);
    float diffCol(int templStart, int bufStart, float maxVal, int shift);

    float *m_inReal;
    float *m_outReal;
    float *m_window;
    FFTSetup m_fftSetup;
    DSPSplitComplex m_splitData;

    // std::ofstream *debugLog;

    float avgBand(std::vector<float> &frame, size_t low, size_t hi);
};



#endif
