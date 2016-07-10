#ifndef _TSSDETECTOR_H_
#define _TSSDETECTOR_H_

#include <vector>

using std::string;

class Detectors {
public:
    Detectors(float inputSampleRate);

    size_t getPreferredBlockSize() const;
    size_t getPreferredStepSize() const;

    bool initialise(size_t channels, size_t stepSize, size_t blockSize);

    int process(const float *const *inputBuffers);

protected:
    // plugin-specific data and methods go here
    int m_blockSize;
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

    float avgBand(std::vector<float> &frame, size_t low, size_t hi);
};



#endif
