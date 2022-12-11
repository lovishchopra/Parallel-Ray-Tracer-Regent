#ifndef __RAY_TRACE_UTIL__
#define __RAY_TRACE_UTIL__

#include <png.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

typedef struct image_size_t {
  int width;
  int height;
} image_size_t; // Store image size

typedef struct
{
    uint8_t red;
    uint8_t green;
    uint8_t blue;
}pixel_t;  // Store pixel color

typedef struct
{
    pixel_t *pixels;
    size_t width;
    size_t height;
}bitmap_t;   // Store pixels

void save_png_to_file (bitmap_t *bitmap, const char *path);
void save_render(char *filename, unsigned char *img, image_size_t image_size);
#endif
