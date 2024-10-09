//
//  ffmpeg.c
//  
//
//  Created by Kyle Erhabor on 5/18/24.
//

#include "ffmpeg.h"
#include "libavutil/avutil.h"
#include "libavutil/error.h"

const int AVERR_EOF = AVERROR_EOF;
const int AVERR_DECODER_NOT_FOUND = AVERROR_DECODER_NOT_FOUND;
const int AVERR_STREAM_NOT_FOUND = AVERROR_STREAM_NOT_FOUND;
const int AVERR_ENOMEM = AVERROR(ENOMEM);
const int AVERR_EAGAIN = AVERROR(EAGAIN);

const int64_t FFAV_NOPTS_VALUE = AV_NOPTS_VALUE;
const int64_t FFAV_TIME_BASE = AV_TIME_BASE;
