//
//  ffmpeg.c
//  
//
//  Created by Kyle Erhabor on 5/18/24.
//

#include "ffmpeg.h"
#include "libavutil/avutil.h"
#include "libavutil/error.h"

const int FFERROR_EOF = AVERROR_EOF;
const int FFERROR_ENOMEM = AVERROR(ENOMEM);
const int FFERROR_EAGAIN = AVERROR(EAGAIN);
const int64_t FF_NOPTS_VALUE = AV_NOPTS_VALUE;
const int64_t FF_TIME_BASE = AV_TIME_BASE;
