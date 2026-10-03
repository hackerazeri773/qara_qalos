#pragma once
#if defined(MSC_VER)
    #define ELNURTTS_EXPORT_API __declspec(dllexport)
    #define ELNURTTS_IMPORT_API __declspec(dllimport)
#else
  #if defined(_WIN32)
    #define ELNURTTS_EXPORT_API [[gnu::dllexport]]
    #define ELNURTTS_IMPORT_API [[gnu::dllimport]]
  #else
    #define ELNURTTS_EXPORT_API [[gnu::visibility("default")]]
    #define ELNURTTS_IMPORT_API
  #endif
#endif
