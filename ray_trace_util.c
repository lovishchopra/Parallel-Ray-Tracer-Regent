#define  _GNU_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include "ray_trace_util.h"

pixel_t * pixel_at (bitmap_t * bitmap, int x, int y)
{
    return bitmap->pixels + bitmap->width * y + x; // Return location of pixel in bitmap
}

void save_png_to_file (bitmap_t *bitmap, const char *path)
{
    FILE * fp;
    png_structp png_ptr = NULL;
    png_infop info_ptr = NULL;
    size_t x, y;
    png_byte ** row_pointers = NULL;
    /* "status" contains the return value of this function. At first
       it is set to a value which means 'failure'. When the routine
       has finished its work, it is set to a value which means
       'success'. */
    /* The following number is set by trial and error only. I cannot
       see where it it is documented in the libpng manual.
    */
    int pixel_size = 3;
    int depth = 8;
    
    fp = fopen (path, "wb");
    if (! fp) {
        abort();
    }

    png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (png_ptr == NULL) {
        abort();
    }
    
    info_ptr = png_create_info_struct (png_ptr);
    if (info_ptr == NULL) {
        abort();
    }
    
    /* Set up error handling. */

    if (setjmp (png_jmpbuf (png_ptr))) {
        abort();
    }
    
    /* Set image attributes. */

    png_set_IHDR (png_ptr,
                  info_ptr,
                  bitmap->width,
                  bitmap->height,
                  depth,
                  PNG_COLOR_TYPE_RGB,
                  PNG_INTERLACE_NONE,
                  PNG_COMPRESSION_TYPE_DEFAULT,
                  PNG_FILTER_TYPE_DEFAULT);
    
    /* Initialize rows of PNG. */

    row_pointers = png_malloc (png_ptr, bitmap->height * sizeof (png_byte *));
    for (y = 0; y < bitmap->height; y++) {
        png_byte *row = 
            png_malloc (png_ptr, sizeof (uint8_t) * bitmap->width * pixel_size);
        row_pointers[y] = row;
        for (x = 0; x < bitmap->width; x++) {
            pixel_t * pixel = pixel_at (bitmap, x, y);  // Store bitmap in image file
            *row++ = pixel->red;
            *row++ = pixel->green;
            *row++ = pixel->blue;
        }
    }
    
    /* Write the image data to "fp". */

    png_init_io (png_ptr, fp);
    png_set_rows (png_ptr, info_ptr, row_pointers);
    png_write_png (png_ptr, info_ptr, PNG_TRANSFORM_IDENTITY, NULL);

    for (y = 0; y < bitmap->height; y++) {
        png_free (png_ptr, row_pointers[y]);
    }
    png_free (png_ptr, row_pointers);
    fclose (fp);
}

void save_render(char *filename, unsigned char *img, image_size_t image_size){
    bitmap_t bitmap;
    pixel_t *pixel;
    bitmap.width = image_size.width;
    bitmap.height = image_size.height;
    bitmap.pixels = malloc(sizeof(pixel_t) * bitmap.width * bitmap.height);

    uint8_t *img_vals = (uint8_t *)img; long long int hw =  image_size.height *  image_size.width;
    for(int i = 0; i < image_size.height; i++){
        for(int j = 0; j < image_size.width; j++){
            pixel = pixel_at(&bitmap, j, i);        // Map the legion rectangle to the bitmap
            pixel->red = img_vals[j *  image_size.height + i];
            pixel->green = img_vals[j *  image_size.height + i + hw];
            pixel->blue = img_vals[j *  image_size.height + i + 2*hw];

        }
    }
    save_png_to_file(&bitmap, filename);
}