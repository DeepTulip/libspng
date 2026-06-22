/* SPDX-License-Identifier: BSD-2-Clause */
#define SPNG__BUILD
#include "spng.h"

#include <stdint.h>
#include <stdlib.h>

#if defined(_WIN32) || defined(__CYGWIN__)
    #define LIBSPNG_EXPORT __declspec(dllexport)
#else
    #define LIBSPNG_EXPORT __attribute__((visibility("default")))
#endif

static int infer_square(uintptr_t byte_size, uint32_t *width, uint32_t *height)
{
    uintptr_t pixels;
    uintptr_t low = 0;
    uintptr_t high;

    if(width == NULL || height == NULL) return 0;
    if(byte_size == 0 || byte_size % 4) return 0;

    pixels = byte_size / 4;
    high = pixels;

    while(low <= high)
    {
        uintptr_t mid = low + (high - low) / 2;
        uintptr_t square;

        if(mid != 0 && mid > UINTPTR_MAX / mid)
        {
            high = mid - 1;
            continue;
        }

        square = mid * mid;

        if(square == pixels)
        {
            if(mid > UINT32_MAX) return 0;

            *width = (uint32_t)mid;
            *height = (uint32_t)mid;
            return 1;
        }

        if(square < pixels) low = mid + 1;
        else high = mid - 1;
    }

    return 0;
}

static void *encode_bgra(const void *pixels, uint32_t width, uint32_t height, int *out_size)
{
    int ret;
    size_t length;
    size_t png_size = 0;
    void *png = NULL;
    spng_ctx *ctx = NULL;
    struct spng_ihdr ihdr = {0};

    if(out_size != NULL) *out_size = 0;
    if(pixels == NULL || out_size == NULL || width == 0 || height == 0) return NULL;
    if(width > SIZE_MAX / height) return NULL;
    if((size_t)width * height > SIZE_MAX / 4) return NULL;

    length = (size_t)width * height * 4;

    ctx = spng_ctx_new(SPNG_CTX_ENCODER);
    if(ctx == NULL) return NULL;

    ret = spng_set_option(ctx, SPNG_ENCODE_TO_BUFFER, 1);
    if(ret) goto error;

    ihdr.width = width;
    ihdr.height = height;
    ihdr.bit_depth = 8;
    ihdr.color_type = SPNG_COLOR_TYPE_TRUECOLOR_ALPHA;

    ret = spng_set_ihdr(ctx, &ihdr);
    if(ret) goto error;

    ret = spng_encode_image(ctx, pixels, length, SPNG_FMT_RGBA8, SPNG_ENCODE_FINALIZE);
    if(ret) goto error;

    png = spng_get_png_buffer(ctx, &png_size, &ret);
    if(png == NULL || ret) goto error;
    if(png_size > INT32_MAX)
    {
        free(png);
        png = NULL;
        goto error;
    }

    *out_size = (int)png_size;
    spng_ctx_free(ctx);
    return png;

error:
    spng_ctx_free(ctx);
    return NULL;
}

LIBSPNG_EXPORT void *SPNG_CDECL enc(const void *pixels, uintptr_t width_or_size, uintptr_t height_or_out_size, int *out_size)
{
    uint32_t width;
    uint32_t height;
    int *size_ptr = out_size;

    if(height_or_out_size > UINT32_MAX)
    {
        size_ptr = (int*)height_or_out_size;

        if(!infer_square(width_or_size, &width, &height)) return NULL;
    }
    else
    {
        if(width_or_size > UINT32_MAX) return NULL;

        width = (uint32_t)width_or_size;
        height = (uint32_t)height_or_out_size;
    }

    return encode_bgra(pixels, width, height, size_ptr);
}

LIBSPNG_EXPORT void SPNG_CDECL enc_free(void *ptr)
{
    free(ptr);
}
