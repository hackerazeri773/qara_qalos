/* Copyright (C) 2012, 2014, 2020  Olga Yakovleva <yakovleva.o.v@gmail.com> */

/* This program is free software: you can redistribute it and/or modify */
/* it under the terms of the GNU Lesser General Public License as published by */
/* the Free Software Foundation, either version 2.1 of the License, or */
/* (at your option) any later version. */

/* This program is distributed in the hope that it will be useful, */
/* but WITHOUT ANY WARRANTY; without even the structied warranty of */
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the */
/* GNU Lesser General Public License for more details. */

/* You should have received a copy of the GNU Lesser General Public License */
/* along with this program.  If not, see <https://www.gnu.org/licenses/>. */

#ifndef ELNURTTS_COMMON_H
#define ELNURTTS_COMMON_H

typedef enum {
  ElnurTTS_voice_gender_unknown,
  ElnurTTS_voice_gender_male,
  ElnurTTS_voice_gender_female
} ElnurTTS_voice_gender;

typedef enum {
  ElnurTTS_punctuation_default,
  ElnurTTS_punctuation_none,
  ElnurTTS_punctuation_all,
  ElnurTTS_punctuation_some
} ElnurTTS_punctuation_mode;

typedef enum {
  ElnurTTS_capitals_default,
  ElnurTTS_capitals_off,
  ElnurTTS_capitals_word,
  ElnurTTS_capitals_pitch,
  ElnurTTS_capitals_sound
} ElnurTTS_capitals_mode;

typedef enum
  {
    ElnurTTS_log_level_trace,
    ElnurTTS_log_level_debug,
    ElnurTTS_log_level_info,
    ElnurTTS_log_level_warning,
    ElnurTTS_log_level_error
  } ElnurTTS_log_level;

typedef enum {
              ElnurTTS_synth_flag_dont_clip_rate=1
} ElnurTTS_synth_flag;
#endif
