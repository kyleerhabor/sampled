//
//  ffmpeg.c
//  
//
//  Created by Kyle Erhabor on 5/18/24.
//

#include "ffmpeg.h"
#include "libavutil/error.h"

int const AVERR_EOF = AVERROR_EOF;
int const AVERR_DECODER_NOT_FOUND = AVERROR_DECODER_NOT_FOUND;
int const AVERR_STREAM_NOT_FOUND = AVERROR_STREAM_NOT_FOUND;
int const AVERR_ENOMEM = AVERROR(ENOMEM);
int const AVERR_EAGAIN = AVERROR(EAGAIN);
