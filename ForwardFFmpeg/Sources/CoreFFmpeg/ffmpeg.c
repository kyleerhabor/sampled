//
//  ffmpeg.c
//  
//
//  Created by Kyle Erhabor on 5/18/24.
//

#include "ffmpeg.h"
#include "libavutil/error.h"

int AVERR_EOF = AVERROR_EOF;
int AVERR_DECODER_NOT_FOUND = AVERROR_DECODER_NOT_FOUND;
int AVERR_STREAM_NOT_FOUND = AVERROR_STREAM_NOT_FOUND;
int AVERR_ENOMEM = AVERROR(ENOMEM);
int AVERR_EAGAIN = AVERROR(EAGAIN);
