/*
 * Copyright (c) 2022 Jonathan Swinney <jswinney@amazon.com>
 *
 * This file is part of FFmpeg.
 *
 * FFmpeg is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * FFmpeg is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FFmpeg; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include "libavutil/aarch64/asm.S"

function ff_pix_abs16_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h
        cmp             w4, #4                      // if h < 4, jump to completion section
        movi            v16.8h, #0                  // clear result accumulator
        movi            v17.8h, #0                  // clear result accumulator
        b.lt            2f
1:
        ld1             {v0.16b}, [x1], x3          // load pix1
        ld1             {v4.16b}, [x2], x3          // load pix2
        ld1             {v1.16b}, [x1], x3          // load pix1
        ld1             {v5.16b}, [x2], x3          // load pix2
        uabal           v16.8h, v0.8b, v4.8b        // absolute difference accumulate
        uabal2          v17.8h, v0.16b, v4.16b
        ld1             {v2.16b}, [x1], x3          // load pix1
        ld1             {v6.16b}, [x2], x3          // load pix2
        uabal           v16.8h, v1.8b, v5.8b        // absolute difference accumulate
        uabal2          v17.8h, v1.16b, v5.16b
        ld1             {v3.16b}, [x1], x3
        ld1             {v7.16b}, [x2], x3
        uabal           v16.8h, v2.8b, v6.8b
        uabal2          v17.8h, v2.16b, v6.16b
        sub             w4, w4, #4                  // h -= 4
        uabal           v16.8h, v3.8b, v7.8b
        uabal2          v17.8h, v3.16b, v7.16b
        cmp             w4, #4                      // if h >= 4, loop

        b.ge            1b
        cbnz            w4, 2f                      // if iterations remain, jump to completion section

        add             v16.8h, v16.8h, v17.8h
        uaddlv          s16, v16.8h                 // add up everything in v16 accumulator
        fmov            w0, s16                     // copy result to general purpose register
        ret

2:
        ld1             {v0.16b}, [x1], x3          // load pix1
        ld1             {v4.16b}, [x2], x3          // load pix2
        subs            w4, w4, #1                  // h -= 1
        uabal           v16.8h, v0.8b, v4.8b        // absolute difference accumulate
        uabal2          v17.8h, v0.16b, v4.16b
        b.ne            2b

        add             v16.8h, v16.8h, v17.8h
        uaddlv          s16, v16.8h                 // add up everything in v16 accumulator
        fmov            w0, s16                     // copy result to general purpose register
        ret
endfunc

function ff_pix_abs16_xy2_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h

        add             x5, x2, x3                  // use x5 to hold uint8_t *pix3
        movi            v21.8h, #0                  // initialize the result register
        movi            v22.8h, #0                  // initialize the result register

        // Load initial pix2 values for either the unrolled version or completion version.
        ldur            q4, [x2, #1]                // load pix2+1
        ldr             q3, [x2]                    // load pix2
        uaddl           v2.8h, v4.8b, v3.8b         // pix2 + pix2+1 0..7
        uaddl2          v3.8h, v4.16b, v3.16b       // pix2 + pix2+1 8..15
        cmp             w4, #4                      // if h < 4 jump to the completion version
        b.lt            2f
1:
        // This is an unrolled implementation. It completes 4 iterations of the C for each branch.
        // In each iteration, pix2[i+1] == pix3[i]. This means we need only three loads per iteration,
        // plus two at the beginning to start.
        ldur            q5, [x5, #1]                // load pix3+1
        ld1             {v4.16b}, [x5], x3          // load pix3
        ld1             {v1.16b}, [x1], x3          // load pix1

        ldur            q7, [x5, #1]                // load pix3+1
        ld1             {v6.16b}, [x5], x3          // load pix3
        ld1             {v16.16b}, [x1], x3         // load pix1

        // These blocks compute the average: avg(pix2[n], pix2[n+1], pix3[n], pix3[n+1])
        uaddl           v30.8h, v4.8b, v5.8b        // pix3 + pix3+1 0..7
        uaddl2          v31.8h, v4.16b, v5.16b      // pix3 + pix3+1 8..15

        ldur            q19, [x5, #1]               // load pix3+1

        add             v23.8h, v2.8h, v30.8h       // add up 0..7, using pix2 + pix2+1 values from previous iteration
        add             v24.8h, v3.8h, v31.8h       // add up 8..15, using pix2 + pix2+1 values from previous iteration

        ld1             {v18.16b}, [x5], x3         // load pix3
        ld1             {v17.16b}, [x1], x3         // load pix1

        rshrn           v23.8b, v23.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v23.16b, v24.8h, #2         // shift right 2 8..15

        uaddl           v2.8h, v6.8b, v7.8b         // pix3 + pix3+1 0..7
        uaddl2          v3.8h, v6.16b, v7.16b       // pix3 + pix3+1 8..15

        ldur            q7, [x5, #1]                // load pix3+1

        add             v26.8h, v30.8h, v2.8h       // add up 0..7, using pix2 + pix2+1 values from pix3 above
        add             v27.8h, v31.8h, v3.8h       // add up 8..15, using pix2 + pix2+1 values from pix3 above

        uabal           v21.8h, v1.8b,  v23.8b      // absolute difference 0..7, i=0
        uabal2          v22.8h, v1.16b, v23.16b     // absolute difference 8..15, i=0

        ld1             {v6.16b}, [x5], x3          // load pix3
        ld1             {v20.16b}, [x1], x3         // load pix1

        rshrn           v26.8b, v26.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v26.16b, v27.8h, #2         // shift right 2 8..15

        uaddl           v4.8h, v18.8b, v19.8b       // pix3 + pix3+1 0..7
        uaddl2          v5.8h, v18.16b, v19.16b     // pix3 + pix3+1 8..15
        add             v28.8h, v2.8h, v4.8h        // add up 0..7, using pix2 + pix2+1 values from pix3 above
        add             v29.8h, v3.8h, v5.8h        // add up 8..15, using pix2 + pix2+1 values from pix3 above
        rshrn           v28.8b, v28.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v28.16b, v29.8h, #2         // shift right 2 8..15

        uabal           v21.8h, v16.8b,  v26.8b     // absolute difference 0..7, i=1
        uabal2          v22.8h, v16.16b, v26.16b    // absolute difference 8..15, i=1

        uaddl           v2.8h, v6.8b,  v7.8b        // pix3 + pix3+1 0..7
        uaddl2          v3.8h, v6.16b, v7.16b       // pix3 + pix3+1 8..15
        add             v30.8h, v4.8h, v2.8h        // add up 0..7, using pix2 + pix2+1 values from pix3 above
        add             v31.8h, v5.8h, v3.8h        // add up 8..15, using pix2 + pix2+1 values from pix3 above
        rshrn           v30.8b, v30.8h, #2          // shift right 2 0..7 (rounding shift right)
        rshrn2          v30.16b, v31.8h, #2         // shift right 2 8..15

        sub             w4, w4, #4                  // h -= 4

        uabal           v21.8h, v17.8b,  v28.8b     // absolute difference 0..7, i=2
        uabal2          v22.8h, v17.16b, v28.16b    // absolute difference 8..15, i=2

        cmp             w4, #4                      // loop if h >= 4


        uabal           v21.8h, v20.8b,  v30.8b     // absolute difference 0..7, i=3
        uabal2          v22.8h, v20.16b, v30.16b    // absolute difference 8..15, i=3

        b.ge            1b
        cbnz            w4, 2f                      // if iterations remain jump to completion section

        add             v4.8h, v21.8h, v22.8h
        uaddlv          s0, v4.8h                   // finish adding up accumulated values

        fmov            w0, s0                      // copy result to general purpose register
        ret
2:
        // v2 and v3 are set either at the end of this loop or at from the unrolled version
        // which branches here to complete iterations when h % 4 != 0.
        ldur            q5, [x5, #1]                // load pix3+1
        ld1             {v4.16b}, [x5], x3          // load pix3
        ld1             {v1.16b}, [x1], x3          // load pix1
        subs            w4, w4, #1                  // decrement h

        uaddl           v18.8h, v4.8b, v5.8b        // pix3 + pix3+1 0..7
        uaddl2          v19.8h, v4.16b, v5.16b      // pix3 + pix3+1 8..15
        add             v16.8h, v2.8h, v18.8h       // add up 0..7, using pix2 + pix2+1 values from previous iteration
        add             v17.8h, v3.8h, v19.8h       // add up 8..15, using pix2 + pix2+1 values from previous iteration
        // divide by 4 to compute the average of values summed above
        rshrn           v16.8b,  v16.8h, #2         // shift right by 2 0..7 (rounding shift right)
        rshrn2          v16.16b, v17.8h, #2         // shift right by 2 8..15

        uabal           v21.8h, v1.8b,  v16.8b      // absolute difference 0..7
        uabal2          v22.8h, v1.16b, v16.16b     // absolute difference accumulate 8..15
        mov             v2.16b, v18.16b             // pix3 -> pix2
        mov             v3.16b, v19.16b             // pix3+1 -> pix2+1

        b.ne            2b                          // loop if h > 0

        add             v4.8h, v21.8h, v22.8h
        uaddlv          s0, v4.8h                   // finish adding up accumulated values
        fmov            w0, s0                      // copy result to general purpose register
        ret
endfunc

function ff_pix_abs16_x2_neon, export=1
        // x0           unused
        // x1           uint8_t *pix1
        // x2           uint8_t *pix2
        // x3           ptrdiff_t stride
        // w4           int h

        cmp             w4, #4
        // initialize buffers
        movi            v16.8h, #0
        movi            v17.8h, #0
        add             x5, x2, #1 // pix2 + 1
        b.lt            2f

// make 4 iterations at once
1:

        // abs(pix1[0] - avg2(pix2[0], pix2[1]))
        // avg2(a,b) = (((a) + (b) + 1) >> 1)
        // abs(x) = (x < 0 ? -x : x)

        ld1             {v1.16b}, [x2], x3
        ld1             {v2.16b}, [x5], x3
        urhadd          v30.16b, v1.16b, v2.16b
        ld1             {v0.16b}, [x1], x3
        uabal           v16.8h, v0.8b, v30.8b
        ld1             {v4.16b}, [x2], x3
        uabal2          v17.8h, v0.16b, v30.16b
        ld1             {v5.16b}, [x5], x3
        urhadd          v29.16b, v4.16b, v5.16b
        ld1             {v3.16b}, [x1], x3
        uabal           v16.8h, v3.8b, v29.8b
        ld1             {v7.16b}, [x2], x3
        uabal2          v17.8h, v3.16b, v29.16b
        ld1             {v22.16b}, [x5], x3
        urhadd          v28.16b, v7.16b, v22.16b
        ld1             {v6.16b}, [x1], x3
        uabal           v16.8h, v6.8b, v28.8b
        ld1             {v24.16b}, [x2], x3
        sub             w4, w4, #4
        uabal2          v17.8h, v6.16b, v28.16b
        ld1             {v25.16b}, [x5], x3
        urhadd          v27.16b, v24.16b, v25.16b
        ld1             {v23.16b}, [x1], x3
        cmp             w4, #4
        uabal           v16.8h, v23.8b, v27.8b
        uabal2          v17.8h, v23.16b, v27.16b

        b.ge            1b
        cbz             w4, 3f

// iterate by one
2:
        ld1             {v1.16b}, [x2], x3
        ld1             {v2.16b}, [x5], x3
        subs            w4, w4, #1
        urhadd          v29.16b, v1.16b, v2.16b
        ld1             {v0.16b}, [x1], x3
        uabal           v16.8h, v0.8b,  v29.8b
        uabal2          v17.8h, v0.16b, v29.16b


        b.ne            2b

3:
        add             v16.8h, v16.8h, v17.8h
        uaddlv          s16, v16.8h
        fmov            w0, s16

        ret
endfunc
