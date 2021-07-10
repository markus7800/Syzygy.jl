module Syzygy

# https://github.com/niklasf/python-chess/blob/master/chess/syzygy.py

using Chess
include("chess+.jl")
import Mmap

export Table, Tablebase

export open_tablebase, get_wdl, probe_wdl, get_dtz, probe_dtz, add_directory

const SQTOPOS = [
    56, 48, 40, 32, 24, 16, 8, 0,
    57, 49, 41, 33, 25, 17, 9, 1,
    58, 50, 42, 34, 26, 18, 10, 2,
    59, 51, 43, 35, 27, 19, 11, 3,
    60, 52, 44, 36, 28, 20, 12, 4,
    61, 53, 45, 37, 29, 21, 13, 5,
    62, 54, 46, 38, 30, 22, 14, 6,
    63, 55, 47, 39, 31, 23, 15, 7
]

const TBPIECES = 7

const OFFDIAG = [
  0,-1,-1,-1,-1,-1,-1,-1,
  1, 0,-1,-1,-1,-1,-1,-1,
  1, 1, 0,-1,-1,-1,-1,-1,
  1, 1, 1, 0,-1,-1,-1,-1,
  1, 1, 1, 1, 0,-1,-1,-1,
  1, 1, 1, 1, 1, 0,-1,-1,
  1, 1, 1, 1, 1, 1, 0,-1,
  1, 1, 1, 1, 1, 1, 1, 0
]

const FLIPDIAG = [
   0,  8, 16, 24, 32, 40, 48, 56,
   1,  9, 17, 25, 33, 41, 49, 57,
   2, 10, 18, 26, 34, 42, 50, 58,
   3, 11, 19, 27, 35, 43, 51, 59,
   4, 12, 20, 28, 36, 44, 52, 60,
   5, 13, 21, 29, 37, 45, 53, 61,
   6, 14, 22, 30, 38, 46, 54, 62,
   7, 15, 23, 31, 39, 47, 55, 63
]

const TRIANGLE = [
    6, 0, 1, 2, 2, 1, 0, 6,
    0, 7, 3, 4, 4, 3, 7, 0,
    1, 3, 8, 5, 5, 8, 3, 1,
    2, 4, 5, 9, 9, 5, 4, 2,
    2, 4, 5, 9, 9, 5, 4, 2,
    1, 3, 8, 5, 5, 8, 3, 1,
    0, 7, 3, 4, 4, 3, 7, 0,
    6, 0, 1, 2, 2, 1, 0, 6,
]

const INVTRIANGLE = [1, 2, 3, 10, 11, 19, 0, 9, 18, 27]

const LOWER = [
    28,  0,  1,  2,  3,  4,  5,  6,
     0, 29,  7,  8,  9, 10, 11, 12,
     1,  7, 30, 13, 14, 15, 16, 17,
     2,  8, 13, 31, 18, 19, 20, 21,
     3,  9, 14, 18, 32, 22, 23, 24,
     4, 10, 15, 19, 22, 33, 25, 26,
     5, 11, 16, 20, 23, 25, 34, 27,
     6, 12, 17, 21, 24, 26, 27, 35,
]

const DIAG = [
     0,  0,  0,  0,  0,  0,  0,  8,
     0,  1,  0,  0,  0,  0,  9,  0,
     0,  0,  2,  0,  0, 10,  0,  0,
     0,  0,  0,  3, 11,  0,  0,  0,
     0,  0,  0, 12,  4,  0,  0,  0,
     0,  0, 13,  0,  0,  5,  0,  0,
     0, 14,  0,  0,  0,  0,  6,  0,
    15,  0,  0,  0,  0,  0,  0,  7,
]

const FLAP = [
    0,  0,  0,  0,  0,  0,  0, 0,
    0,  6, 12, 18, 18, 12,  6, 0,
    1,  7, 13, 19, 19, 13,  7, 1,
    2,  8, 14, 20, 20, 14,  8, 2,
    3,  9, 15, 21, 21, 15,  9, 3,
    4, 10, 16, 22, 22, 16, 10, 4,
    5, 11, 17, 23, 23, 17, 11, 5,
    0,  0,  0,  0,  0,  0,  0, 0,
]

const PTWIST = [
     0,  0,  0,  0,  0,  0,  0,  0,
    47, 35, 23, 11, 10, 22, 34, 46,
    45, 33, 21,  9,  8, 20, 32, 44,
    43, 31, 19,  7,  6, 18, 30, 42,
    41, 29, 17,  5,  4, 16, 28, 40,
    39, 27, 15,  3,  2, 14, 26, 38,
    37, 25, 13,  1,  0, 12, 24, 36,
     0,  0,  0,  0,  0,  0,  0,  0,
]

const INVFLAP = [
     8, 16, 24, 32, 40, 48,
     9, 17, 25, 33, 41, 49,
    10, 18, 26, 34, 42, 50,
    11, 19, 27, 35, 43, 51,
]

const FILE_TO_FILE = [0, 1, 2, 3, 3, 2, 1, 0]

const KK_IDX = [[
     -1,  -1,  -1,   0,   1,   2,   3,   4,
     -1,  -1,  -1,   5,   6,   7,   8,   9,
     10,  11,  12,  13,  14,  15,  16,  17,
     18,  19,  20,  21,  22,  23,  24,  25,
     26,  27,  28,  29,  30,  31,  32,  33,
     34,  35,  36,  37,  38,  39,  40,  41,
     42,  43,  44,  45,  46,  47,  48,  49,
     50,  51,  52,  53,  54,  55,  56,  57,
], [
     58,  -1,  -1,  -1,  59,  60,  61,  62,
     63,  -1,  -1,  -1,  64,  65,  66,  67,
     68,  69,  70,  71,  72,  73,  74,  75,
     76,  77,  78,  79,  80,  81,  82,  83,
     84,  85,  86,  87,  88,  89,  90,  91,
     92,  93,  94,  95,  96,  97,  98,  99,
    100, 101, 102, 103, 104, 105, 106, 107,
    108, 109, 110, 111, 112, 113, 114, 115,
], [
    116, 117,  -1,  -1,  -1, 118, 119, 120,
    121, 122,  -1,  -1,  -1, 123, 124, 125,
    126, 127, 128, 129, 130, 131, 132, 133,
    134, 135, 136, 137, 138, 139, 140, 141,
    142, 143, 144, 145, 146, 147, 148, 149,
    150, 151, 152, 153, 154, 155, 156, 157,
    158, 159, 160, 161, 162, 163, 164, 165,
    166, 167, 168, 169, 170, 171, 172, 173,
], [
    174,  -1,  -1,  -1, 175, 176, 177, 178,
    179,  -1,  -1,  -1, 180, 181, 182, 183,
    184,  -1,  -1,  -1, 185, 186, 187, 188,
    189, 190, 191, 192, 193, 194, 195, 196,
    197, 198, 199, 200, 201, 202, 203, 204,
    205, 206, 207, 208, 209, 210, 211, 212,
    213, 214, 215, 216, 217, 218, 219, 220,
    221, 222, 223, 224, 225, 226, 227, 228,
], [
    229, 230,  -1,  -1,  -1, 231, 232, 233,
    234, 235,  -1,  -1,  -1, 236, 237, 238,
    239, 240,  -1,  -1,  -1, 241, 242, 243,
    244, 245, 246, 247, 248, 249, 250, 251,
    252, 253, 254, 255, 256, 257, 258, 259,
    260, 261, 262, 263, 264, 265, 266, 267,
    268, 269, 270, 271, 272, 273, 274, 275,
    276, 277, 278, 279, 280, 281, 282, 283,
], [
    284, 285, 286, 287, 288, 289, 290, 291,
    292, 293,  -1,  -1,  -1, 294, 295, 296,
    297, 298,  -1,  -1,  -1, 299, 300, 301,
    302, 303,  -1,  -1,  -1, 304, 305, 306,
    307, 308, 309, 310, 311, 312, 313, 314,
    315, 316, 317, 318, 319, 320, 321, 322,
    323, 324, 325, 326, 327, 328, 329, 330,
    331, 332, 333, 334, 335, 336, 337, 338,
], [
     -1,  -1, 339, 340, 341, 342, 343, 344,
     -1,  -1, 345, 346, 347, 348, 349, 350,
     -1,  -1, 441, 351, 352, 353, 354, 355,
     -1,  -1,  -1, 442, 356, 357, 358, 359,
     -1,  -1,  -1,  -1, 443, 360, 361, 362,
     -1,  -1,  -1,  -1,  -1, 444, 363, 364,
     -1,  -1,  -1,  -1,  -1,  -1, 445, 365,
     -1,  -1,  -1,  -1,  -1,  -1,  -1, 446,
], [
     -1,  -1,  -1, 366, 367, 368, 369, 370,
     -1,  -1,  -1, 371, 372, 373, 374, 375,
     -1,  -1,  -1, 376, 377, 378, 379, 380,
     -1,  -1,  -1, 447, 381, 382, 383, 384,
     -1,  -1,  -1,  -1, 448, 385, 386, 387,
     -1,  -1,  -1,  -1,  -1, 449, 388, 389,
     -1,  -1,  -1,  -1,  -1,  -1, 450, 390,
     -1,  -1,  -1,  -1,  -1,  -1,  -1, 451,
], [
    452, 391, 392, 393, 394, 395, 396, 397,
     -1,  -1,  -1,  -1, 398, 399, 400, 401,
     -1,  -1,  -1,  -1, 402, 403, 404, 405,
     -1,  -1,  -1,  -1, 406, 407, 408, 409,
     -1,  -1,  -1,  -1, 453, 410, 411, 412,
     -1,  -1,  -1,  -1,  -1, 454, 413, 414,
     -1,  -1,  -1,  -1,  -1,  -1, 455, 415,
     -1,  -1,  -1,  -1,  -1,  -1,  -1, 456,
], [
    457, 416, 417, 418, 419, 420, 421, 422,
     -1, 458, 423, 424, 425, 426, 427, 428,
     -1,  -1,  -1,  -1,  -1, 429, 430, 431,
     -1,  -1,  -1,  -1,  -1, 432, 433, 434,
     -1,  -1,  -1,  -1,  -1, 435, 436, 437,
     -1,  -1,  -1,  -1,  -1, 459, 438, 439,
     -1,  -1,  -1,  -1,  -1,  -1, 460, 440,
     -1,  -1,  -1,  -1,  -1,  -1,  -1, 461,
]]

const PP_IDX = [[
      0,  -1,   1,   2,   3,   4,   5,   6,
      7,   8,   9,  10,  11,  12,  13,  14,
     15,  16,  17,  18,  19,  20,  21,  22,
     23,  24,  25,  26,  27,  28,  29,  30,
     31,  32,  33,  34,  35,  36,  37,  38,
     39,  40,  41,  42,  43,  44,  45,  46,
     -1,  47,  48,  49,  50,  51,  52,  53,
     54,  55,  56,  57,  58,  59,  60,  61,
], [
     62,  -1,  -1,  63,  64,  65,  -1,  66,
     -1,  67,  68,  69,  70,  71,  72,  -1,
     73,  74,  75,  76,  77,  78,  79,  80,
     81,  82,  83,  84,  85,  86,  87,  88,
     89,  90,  91,  92,  93,  94,  95,  96,
     -1,  97,  98,  99, 100, 101, 102, 103,
     -1, 104, 105, 106, 107, 108, 109,  -1,
    110,  -1, 111, 112, 113, 114,  -1, 115,
], [
    116,  -1,  -1,  -1, 117,  -1,  -1, 118,
     -1, 119, 120, 121, 122, 123, 124,  -1,
     -1, 125, 126, 127, 128, 129, 130,  -1,
    131, 132, 133, 134, 135, 136, 137, 138,
     -1, 139, 140, 141, 142, 143, 144, 145,
     -1, 146, 147, 148, 149, 150, 151,  -1,
     -1, 152, 153, 154, 155, 156, 157,  -1,
    158,  -1,  -1, 159, 160,  -1,  -1, 161,
], [
    162,  -1,  -1,  -1,  -1,  -1,  -1, 163,
     -1, 164,  -1, 165, 166, 167, 168,  -1,
     -1, 169, 170, 171, 172, 173, 174,  -1,
     -1, 175, 176, 177, 178, 179, 180,  -1,
     -1, 181, 182, 183, 184, 185, 186,  -1,
     -1,  -1, 187, 188, 189, 190, 191,  -1,
     -1, 192, 193, 194, 195, 196, 197,  -1,
    198,  -1,  -1,  -1,  -1,  -1,  -1, 199,
], [
    200,  -1,  -1,  -1,  -1,  -1,  -1, 201,
     -1, 202,  -1,  -1, 203,  -1, 204,  -1,
     -1,  -1, 205, 206, 207, 208,  -1,  -1,
     -1, 209, 210, 211, 212, 213, 214,  -1,
     -1,  -1, 215, 216, 217, 218, 219,  -1,
     -1,  -1, 220, 221, 222, 223,  -1,  -1,
     -1, 224,  -1, 225, 226,  -1, 227,  -1,
    228,  -1,  -1,  -1,  -1,  -1,  -1, 229,
], [
    230,  -1,  -1,  -1,  -1,  -1,  -1, 231,
     -1, 232,  -1,  -1,  -1,  -1, 233,  -1,
     -1,  -1, 234,  -1, 235, 236,  -1,  -1,
     -1,  -1, 237, 238, 239, 240,  -1,  -1,
     -1,  -1,  -1, 241, 242, 243,  -1,  -1,
     -1,  -1, 244, 245, 246, 247,  -1,  -1,
     -1, 248,  -1,  -1,  -1,  -1, 249,  -1,
    250,  -1,  -1,  -1,  -1,  -1,  -1, 251,
], [
     -1,  -1,  -1,  -1,  -1,  -1,  -1, 259,
     -1, 252,  -1,  -1,  -1,  -1, 260,  -1,
     -1,  -1, 253,  -1,  -1, 261,  -1,  -1,
     -1,  -1,  -1, 254, 262,  -1,  -1,  -1,
     -1,  -1,  -1,  -1, 255,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1, 256,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1, 257,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1, 258,
], [
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1, 268,  -1,
     -1,  -1, 263,  -1,  -1, 269,  -1,  -1,
     -1,  -1,  -1, 264, 270,  -1,  -1,  -1,
     -1,  -1,  -1,  -1, 265,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1, 266,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1, 267,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
], [
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1, 274,  -1,  -1,
     -1,  -1,  -1, 271, 275,  -1,  -1,  -1,
     -1,  -1,  -1,  -1, 272,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1, 273,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
], [
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1, 277,  -1,  -1,  -1,
     -1,  -1,  -1,  -1, 276,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
     -1,  -1,  -1,  -1,  -1,  -1,  -1,  -1,
]]

# test45 only for non standard variant

const MTWIST = [
    15, 63, 55, 47, 40, 48, 56, 12,
    62, 11, 39, 31, 24, 32,  8, 57,
    54, 38,  7, 23, 16,  4, 33, 49,
    46, 30, 22,  3,  0, 17, 25, 41,
    45, 29, 21,  2,  1, 18, 26, 42,
    53, 37,  6, 20, 19,  5, 34, 50,
    61, 10, 36, 28, 27, 35,  9, 58,
    14, 60, 52, 44, 43, 51, 59, 13,
]

const PAWNIDX = zeros(Int, 5, 24)
const PFACTOR = zeros(Int, 5, 4)

for i in 0:4
    j = 0

    s = 0
    while j < 6
        PAWNIDX[i+1,j+1] = s
        s += (i == 0 ? 1 : binomial(PTWIST[INVFLAP[j+1]+1], i))
        j += 1
    end
    PFACTOR[i+1,0+1] = s

    s = 0
    while j < 12
        PAWNIDX[i+1,j+1] = s
        s += (i == 0 ? 1 : binomial(PTWIST[INVFLAP[j+1]+1], i))
        j += 1
    end
    PFACTOR[i+1,1+1] = s

    s = 0
    while j < 18
        PAWNIDX[i+1,j+1] = s
        s += (i == 0 ? 1 : binomial(PTWIST[INVFLAP[j+1]+1], i))
        j += 1
    PFACTOR[i+1,2+1] = s
    end
    s = 0
    while j < 24
        PAWNIDX[i+1,j+1] = s
        s += (i == 0 ? 1 : binomial(PTWIST[INVFLAP[j+1]+1], i))
        j += 1
    end
    PFACTOR[i+1,3+1] = s
end

const MULTIDX = zeros(Int, 5, 10)

const MFACTOR = zeros(Int, 5)

for i in 0:4
    s = 0
    for j in 0:9
        MULTIDX[i+1,j+1] = s
        s += (i == 0 ? 1 : binomial(MTWIST[INVTRIANGLE[j+1]+1], i))
        end
    MFACTOR[i+1] = s
end


const WDL_TO_MAP = [1, 3, 0, 2, 0]

const PA_FLAGS = [8, 0, 0, 0, 4]

const WDL_TO_DTZ = [-1, -101, 0, 101, 1]

const PCHR = ['K', 'Q', 'R', 'B', 'N', 'P']

const PCHRindex = Dict(zip(PCHR, 1:length(PCHR)))

const TABLENAME_REGEX = r"^[KQRBNP]+v[KQRBNP]+\Z"

function is_tablename(name::String; piece_count::Int = TBPIECES, normalized::Bool = true)::Bool
    return (length(name) <= piece_count + 1) &&
        !isnothing(match(TABLENAME_REGEX, name)) &&
        (!normalized || normalize_tablename(name) == name) &&
        (name != "KvK" && startswith(name, "K") && occursin("vK",name))
end


function normalize_tablename(name::String; mirror::Bool = false)::String
    w, b = split(name, "v")
    w = join(sort(collect(w), by=c->PCHRindex[c]))
    b = join(sort(collect(b), by=c->PCHRindex[c]))
    if mirror ⊻ ((length(w), [PCHRindex[c] for c in b]) < (length(b), [PCHRindex[c] for c in w]))
        return b * "v" * w
    else
        return w * "v" * b
    end
end


function calc_key(board::Board;  mirror::Bool = false)::String
    w = !mirror ? WHITE : BLACK
    b = !mirror ? BLACK : WHITE

    return join([
        "K" ^ squarecount(kings(board, w)),
        "Q" ^ squarecount(queens(board, w)),
        "R" ^ squarecount(rooks(board, w)),
        "B" ^ squarecount(bishops(board, w)),
        "N" ^ squarecount(knights(board, w)),
        "P" ^ squarecount(pawns(board, w)),
        "v",
        "K" ^ squarecount(kings(board, b)),
        "Q" ^ squarecount(queens(board, b)),
        "R" ^ squarecount(rooks(board, b)),
        "B" ^ squarecount(bishops(board, b)),
        "N" ^ squarecount(knights(board, b)),
        "P" ^ squarecount(pawns(board, b)),
    ])
end

function recalc_key(pieces_val::Vector{Int}; mirror::Bool=false)
     w = mirror ? 8 : 0
     b = mirror ? 0 : 8

     return join([
         "K" ^ count(==(6 ⊻ w), pieces_val),
         "Q" ^ count(==(5 ⊻ w), pieces_val),
         "R" ^ count(==(4 ⊻ w), pieces_val),
         "B" ^ count(==(3 ⊻ w), pieces_val),
         "N" ^ count(==(2 ⊻ w), pieces_val),
         "P" ^ count(==(1 ⊻ w), pieces_val),
         "v",
         "K" ^ count(==(6 ⊻ b), pieces_val),
         "Q" ^ count(==(5 ⊻ b), pieces_val),
         "R" ^ count(==(4 ⊻ b), pieces_val),
         "B" ^ count(==(3 ⊻ b), pieces_val),
         "N" ^ count(==(2 ⊻ b), pieces_val),
         "P" ^ count(==(1 ⊻ b), pieces_val),
     ])
end

function recalc_key(pieces::Vector{Piece}; mirror::Bool=false)

     pieces_val = map(x -> x.val, pieces)

     return recalc_key(pieces_val, mirror = mirror)
end

function subfactor(k::Int, n::Int)::Int
    f = n
    l = 1

    for i in 1:(k-1)
        f *= n - i
        l *= i + 1
    end

    return f ÷ l
end

function dtz_before_zeroing(wdl::Int)::Int
    return ((wdl > 0) - (wdl < 0)) * (abs(wdl) == 2 ? 1 : 101)
end


mutable struct PairsData
    indextable::Int
    sizetable::Int
    data::Int
    offset::Int
    symlen::Vector{Int}
    sympat::Int
    blocksize::Int
    idxbits::Int
    min_len::Int
    base::Vector{BigInt}

    function PairsData()
        return new()
    end
end

function Base.show(io::IO, d::PairsData)
    print(io, "PairsData object")
end

mutable struct PawnFileData
    precomp::Dict{Int, PairsData}
    factor::Dict{Int, Vector{Int}}
    pieces::Dict{Int, Vector{Int}}
    norm::Dict{Int, Vector{Int}}

    function PawnFileData()
        return new(
            Dict{Int, PairsData}(),
            Dict{Int, Vector{Int}}(),
            Dict{Int, Vector{Int}}(),
            Dict{Int, Vector{Int}}()
            )
    end
end


function Base.show(io::IO, f::PawnFileData)
    print(io, "PawnFileData object")
end

mutable struct PawnFileDataDtz
    precomp::PairsData
    factor::Vector{Int}
    pieces::Vector{Int}
    norm::Vector{Int}
    function PawnFileDataDtz()
        return new()
    end
end

function Base.show(io::IO, f::PawnFileDataDtz)
    print(io, "PawnFileDataDtz object")
end

mutable struct Table
    size::Vector{Int}
    tb_size::Vector{Int}

    path::String

    initialized::Bool

    fd::Union{IOStream, Missing}
    data::Union{Vector{UInt8}, Missing}

    read_count::Int

    key::String
    mirrored_key::String
    symmetric::Bool

    num::Int

    has_pawns::Bool
    pawns::Dict{Int,Int}

    enc_type::Int

    _next::Int
    _flags::Int

    precomp::Dict{Int, PairsData}
    factor::Dict{Int, Vector{Int}}
    pieces::Dict{Int, Vector{Int}}
    norm::Dict{Int, Vector{Int}}
    files::Vector{PawnFileData}

    dtz_precomp::PairsData
    dtz_factor::Vector{Int}
    dtz_pieces::Vector{Int}
    dtz_norm::Vector{Int}
    dtz_files::Vector{PawnFileDataDtz}
    p_map::Int

    dtz_flags::Union{Int, Vector{Int}}

    map_idx::Vector{Vector{Int}}

    type::Symbol

    function Table(path::String)
        tb = new()

        tb.path = path
        # only standard variant

        tb.initialized = false

        tb.fd = missing
        tb.data = missing

        tb.read_count = 0

        tablename, = String.(splitext(basename(path)))
        tb.key = normalize_tablename(tablename)
        tb.mirrored_key = normalize_tablename(tablename, mirror=true)
        tb.symmetric = tb.key == tb.mirrored_key

        tb.num = length(tablename) - 1 # minus "v"

        tb.has_pawns = 'P' in tablename

        black_part, white_part = split(tablename, "v")
        if tb.has_pawns
            tb.pawns = Dict(
                0 => count(==('P'), white_part),
                1 => count(==('P'), black_part)
            )
            if tb.pawns[1] > 0 && (tb.pawns[0] == 0 || tb.pawns[1] < tb.pawns[0])
                stmp = tb.pawns[0]
                tb.pawns[0] = tb.pawns[1]
                tb.pawns[1] = stmp
            end
        else
            j = 0
            for piece_type in PCHR
                if count(==(piece_type), black_part) == 1
                    j += 1
                end
                if count(==(piece_type), white_part) == 1
                    j += 1
                end
            end
            if j >= 3
                tb.enc_type = 0
            else
                tb.enc_type = 2
            end
        end

        tb._next = 0
        tb._flags = 0

        return tb
    end
end

function read_uint64(tb::Table, data_ptr::Int)
    return reinterpret(UInt64, tb.data[(data_ptr+1):(data_ptr+8)])[1]
end

function read_uint64_be(tb::Table, data_ptr::Int)
    return ntoh(read_uint64(tb, data_ptr))
end

function read_uint32(tb::Table, data_ptr::Int)
    return reinterpret(UInt32, tb.data[(data_ptr+1):(data_ptr+4)])[1]
end

function read_uint32_be(tb::Table, data_ptr::Int)
    return ntoh(read_uint32(tb, data_ptr))
end

function read_uint16(tb::Table, data_ptr::Int)
    return reinterpret(UInt16, tb.data[(data_ptr+1):(data_ptr+2)])[1]
end

function read_uint16_be(tb::Table, data_ptr::Int)
    return ntoh(read_uint16(tb, data_ptr))
end

function read_byte(tb::Table, data_ptr::Integer)
    return Int(tb.data[data_ptr + 1])
end

function Base.show(io::IO, tb::Table)
    print(io, "Table{$(tb.key), $(tb.num)}")
end

function init_mmap(tb::Table)
    if ismissing(tb.fd)
        tb.fd = open(tb.path) # default is read only
    end

    if ismissing(tb.data)
        data = Mmap.mmap(tb.fd)
        if length(data) % 64 != 16
            error("Invalid file size!")
        end
        tb.data = data
    end
end

function check_magic(tb::Table, magic::Base.CodeUnits)
    @assert !ismissing(tb.data)

    if tb.data[1:min(4,length(tb.data))] != magic
        error("Invalid magic header!")
    end
end

function setup_pairs(tb::Table, data_ptr::Int, tb_size::Int, size_idx::Int, wdl::Bool)::PairsData
    @assert !ismissing(tb.data)

    d = PairsData()

    tb._flags = read_byte(tb, data_ptr)# tb.data[data_ptr + 1]
    if (read_byte(tb, data_ptr) & Int(0x80)) != 0 # tb.data[data_ptr + 1]
        d.idxbits = 0
        if wdl
            d.min_len = read_byte(tb, data_ptr + 1) # tb.data[data_ptr + 1 + 1]
        else
            d.min_len = 0
        end
        tb._next = data_ptr + 2
        tb.size[size_idx + 0 + 1] = 0
        tb.size[size_idx + 1 + 1] = 0
        tb.size[size_idx + 2 + 1] = 0
        return d
    end

    d.blocksize = read_byte(tb, data_ptr + 1) #tb.data[data_ptr + 1 + 1]
    d.idxbits = read_byte(tb, data_ptr + 2) #tb.data[data_ptr + 2 + 1]

    real_num_blocks = read_uint32(tb, data_ptr + 4)
    num_blocks = real_num_blocks + read_byte(tb, data_ptr + 3) #tb.data[data_ptr + 3 + 1]
    max_len = read_byte(tb, data_ptr + 8) #tb.data[data_ptr + 8 + 1]
    min_len = read_byte(tb, data_ptr + 9) # tb.data[data_ptr + 9 + 1]
    h = max_len - min_len + 1
    num_syms = read_uint16(tb, data_ptr + 10 + 2 * h)

    d.offset = data_ptr + 10
    d.symlen = zeros(Int, h * 8 + num_syms)
    d.sympat = data_ptr + 12 + 2 * h
    d.min_len = min_len

    tb._next = data_ptr + 12 + 2 * h + 3 * num_syms + (num_syms & 1)

    num_indices = (tb_size + (1 << d.idxbits) - 1) >> d.idxbits
    tb.size[size_idx + 0 + 1] = 6 * num_indices
    tb.size[size_idx + 1 + 1] = 2 * num_blocks
    tb.size[size_idx + 2 + 1] = (1 << d.blocksize) * real_num_blocks

    tmp = zeros(Int, num_syms)
    for i in 0:(num_syms-1)
        if tmp[i + 1] == 0
            calc_symlen(tb, d, i, tmp)
        end
    end

    d.base = zeros(Int, h)
    d.base[h - 1 + 1] = 0
    for i in (h-2):-1:0#range(h - 2, -1, -1):
        d.base[i + 1] = (d.base[i + 1 + 1] + read_uint16(tb, d.offset + i * 2) - read_uint16(tb, d.offset + i * 2 + 2)) ÷ 2
    end
    for i in 0:(h-1)#range(h):
        d.base[i + 1] <<= 64 - (min_len + i)
    end

    d.offset -= 2 * d.min_len

    return d
end

function set_norm_piece(tb::Table, norm::Vector{Int}, pieces::Vector{Int})
    #println(tb.num, ", ", tb.enc_type)
    if tb.enc_type == 0
        norm[0 + 1] = 3
    elseif tb.enc_type == 2
        norm[0 + 1] = 2
    else
        norm[0 + 1] = tb.enc_type - 1
    end

    i = norm[0 + 1]
    while i < tb.num
        j = i
        while j < tb.num && pieces[j + 1] == pieces[i + 1]
            norm[i + 1] += 1
            j += 1
        end
        i += norm[i + 1]
        #println(norm)
    end
end

function calc_factors_piece(tb::Table, factor::Vector{Int}, order::Int, norm::Vector{Int})::Int

    PIVFAC = [31332, 28056, 462]

    n = 64 - norm[0 + 1]

    f = 1
    i = norm[0 + 1]
    k = 0
    while i < tb.num || k == order
        if k == order
            factor[0 + 1] = f
            if tb.enc_type < 4
                f *= PIVFAC[tb.enc_type + 1]
            else
                f *= MFACTOR[tb.enc_type - 2 + 1]
            end
        else
            factor[i + 1] = f
            f *= subfactor(norm[i + 1], n)
            n -= norm[i + 1]
            i += norm[i + 1]
        end
        k += 1
    end

    return f
end

function calc_factors_pawn(tb::Table, factor::Vector{Int}, order::Int, order2::Int, norm::Vector{Int}, f::Int)::Int
    i = norm[0 + 1]
    if order2 < Int(0x0f)
        i += norm[i + 1]
    end
    n = 64 - i

    fac = 1
    k = 0
    while i < tb.num || k in [order, order2]
        if k == order
            factor[0 + 1] = fac
            fac *= PFACTOR[norm[0 + 1] - 1 + 1, f + 1]
        elseif k == order2
            factor[norm[0 + 1] + 1] = fac
            fac *= subfactor(norm[norm[0 + 1] + 1], 48 - norm[0 + 1])
        else
            factor[i + 1] = fac
            fac *= subfactor(norm[i + 1], n)
            n -= norm[i + 1]
            i += norm[i + 1]
        end
        k += 1
    end

    return fac
end

function set_norm_pawn(tb::Table, norm::Vector{Int}, pieces::Vector{Int})
    norm[0 + 1] = tb.pawns[0]
    if tb.pawns[1] != 0
        norm[tb.pawns[0] + 1] = tb.pawns[1]
    end

    i = tb.pawns[0] + tb.pawns[1]
    while i < tb.num
        j = i
        while j < tb.num && pieces[j + 1] == pieces[i + 1]
            norm[i + 1] += 1
            j += 1
        end
        i += norm[i + 1]
    end
end

function calc_symlen(tb::Table, d::PairsData, s::Int, tmp::Vector{Int})
    @assert !ismissing(tb.data)

    w = d.sympat + 3 * s
    s2 = (read_byte(tb, w + 2) << 4) | (read_byte(tb, w + 1) >> 4) # (tb.data[w + 2 + 1] << 4) | (tb.data[w + 1 + 1] >> 4)
    #println("symlen: ", Int(s), " ", Int(w), " ", Int(s2))
    if s2 == Int(0x0fff)
        d.symlen[s + 1] = 0
    else
        s1 = ((read_byte(tb, w + 1) & Int(0xf)) << 8) | read_byte(tb, w) #((tb.data[w + 1 + 1] & 0xf) << 8) | tb.data[w + 1]
        if tmp[s1 + 1] == 0
            calc_symlen(tb, d, s1, tmp)
        end
        if tmp[s2 + 1] == 0
            calc_symlen(tb, d, s2, tmp)
        end
        d.symlen[s + 1] = d.symlen[s1 + 1] + d.symlen[s2 + 1] + 1
    end
    tmp[s + 1] = 1
end

function pawn_file(tb::Table, pos::Vector{Int})::Int
    for i in 1:(tb.pawns[0] - 1)
        if FLAP[pos[0 + 1] + 1] > FLAP[pos[i + 1] + 1]
            stmp = pos[0 + 1]
            pos[0 + 1] = pos[i + 1]
            pos[i + 1] = stmp
        end
    end

    return FILE_TO_FILE[(pos[0 + 1] & Int(0x07)) + 1]
end

function encode_piece(tb::Table, norm::Vector{Int}, pos::Vector{Int}, factor::Vector{Int})::Int
    n = tb.num

    if tb.enc_type < 3
        if (pos[0 + 1] & Int(0x04)) != 0
            for i in 0:(n-1)
                pos[i + 1] ⊻= Int(0x07)
            end
        end

        if (pos[0 + 1] & Int(0x20)) != 0
            for i in 0:(n-1)
                pos[i + 1] ⊻= Int(0x38)
            end
        end

        local i
        for ii in 0:(n-1)#range(n):
            i = ii
            if OFFDIAG[pos[ii + 1] + 1] != 0
                break
            end
        end

        if i < (tb.enc_type == 0 ? 3 : 2) && OFFDIAG[pos[i + 1] + 1] > 0
            for i in 0:(n-1)#range(n):
                pos[i + 1] = FLIPDIAG[pos[i + 1] + 1]
            end
        end
    end

    if tb.enc_type == 0  # 111
        i = Int(pos[1 + 1] > pos[0 + 1])
        j = Int(pos[2 + 1] > pos[0 + 1]) + Int(pos[2 + 1] > pos[1 + 1])

        if OFFDIAG[pos[0 + 1] + 1] != 0
            idx = TRIANGLE[pos[0 + 1] + 1] * 63 * 62 + (pos[1 + 1] - i) * 62 + (pos[2 + 1] - j)
        elseif OFFDIAG[pos[1 + 1] + 1] != 0
            idx = 6 * 63 * 62 + DIAG[pos[0 + 1] + 1] * 28 * 62 + LOWER[pos[1 + 1] + 1] * 62 + pos[2 + 1] - j
        elseif OFFDIAG[pos[2 + 1] + 1] != 0
            idx = 6 * 63 * 62 + 4 * 28 * 62 + (DIAG[pos[0 + 1] + 1]) * 7 * 28 + (DIAG[pos[1 + 1] + 1] - i) * 28 + LOWER[pos[2 + 1] + 1]
        else
            idx = 6 * 63 * 62 + 4 * 28 * 62 + 4 * 7 * 28 + (DIAG[pos[0 + 1] + 1] * 7 * 6) + (DIAG[pos[1 + 1] + 1] - i) * 6 + (DIAG[pos[2 + 1] + 1] - j)
        end
        i = 3
    elseif tb.enc_type == 2  # K2
        idx = KK_IDX[TRIANGLE[pos[0 + 1] + 1] + 1][pos[1 + 1] + 1]
        i = 2
    else
        error("None-standard variants not supported!")
    end

    idx *= factor[0 + 1]

    while i < n
        t = norm[i + 1]

        for j in i:(i + t - 1)#range(i, i + t):
            for k in (j + 1):(i + t - 1)#range(j + 1, i + t):
                # Swap.
                if pos[j + 1] > pos[k + 1]
                    stmp = pos[j + 1]
                    pos[j + 1] = pos[k + 1]
                    pos[k + 1] = stmp
                end
            end
        end

        s = 0

        for m in i:(i + t - 1)#range(i, i + t):
            p = pos[m + 1]
            j = 0
            for l in 0:(i-1)#range(i):
                j += Int(p > pos[l + 1])
            end
            s += binomial(p - j, m - i + 1)
        end

        idx += s * factor[i + 1]
        i += t
    end

    return idx
end

function encode_pawn(tb::Table, norm::Vector{Int}, pos::Vector{Int}, factor::Vector{Int})::Int
    n = tb.num

    if (pos[0 + 1] & Int(0x04)) != 0
        for i in 0:(n-1)#range(n):
            pos[i + 1] ⊻= Int(0x07)
        end
    end

    for i in 1:(tb.pawns[0]-1)#range(1, tb.pawns[0]):
        for j in (i + 1):(tb.pawns[0] - 1)#range(i + 1, tb.pawns[0]):
            if PTWIST[pos[i + 1] + 1] < PTWIST[pos[j + 1] + 1]
                stmp = pos[i + 1]
                pos[i + 1] = pos[j + 1]
                pos[j + 1] = stmp
            end
        end
    end
    t = tb.pawns[0] - 1
    idx = PAWNIDX[t + 1, FLAP[pos[0 + 1] + 1] + 1]
    for i in t:-1:1#range(t, 0, -1):
        idx += binomial(PTWIST[pos[i + 1] + 1], t - i + 1)
    end
    idx *= factor[0 + 1]

    # Remaining pawns.
    i = tb.pawns[0]
    t = i + tb.pawns[1]
    if t > i
        for j in i:(t-1)#range(i, t):
            for k in (j+1):(t-1)#range(j + 1, t):
                if pos[j + 1] > pos[k + 1]
                    stmp = pos[j + 1]
                    pos[j + 1] = pos[k + 1]
                    pos[k + 1] = stmp
                end
            end
        end

        s = 0
        for m in i:(t-1)#range(i, t):
            p = pos[m + 1]
            j = 0
            for k in 0:(i-1)#range(i):
                j += Int(p > pos[k + 1])
            end
            s += binomial(p - j - 8, m - i + 1)
        end
        idx += s * factor[i + 1]
        i = t
    end

    while i < n
        t = norm[i + 1]
        for j in i:(i + t - 1)#range(i, i + t):
            for k in (j + 1):(i + t - 1)#range(j + 1, i + t):
                if pos[j + 1] > pos[k + 1]
                    stmp = pos[j + 1]
                    pos[j + 1] = pos[k + 1]
                    pos[k + 1] = stmp
                end
            end
        end

        s = 0
        for m in i:(i + t - 1)#range(i, i + t):
            p = pos[m + 1]
            j = 0
            for k in 0:(i - 1)#range(i):
                j += Int(p > pos[k + 1])
            end
            s += binomial(p - j, m - i + 1)
        end

        idx += s * factor[i + 1]
        i += t
    end

    return idx
end

function decompress_pairs(tb::Table, d::PairsData, idx::Int)::Int
    @assert !ismissing(tb.data)

    if d.idxbits == 0
        return d.min_len
    end

    mainidx = idx >> d.idxbits
    litidx = (idx & ((1 << d.idxbits) - 1)) - (1 << (d.idxbits - 1))
    block = read_uint32(tb, d.indextable + 6 * mainidx)

    idx_offset = read_uint16(tb, d.indextable + 6 * mainidx + 4)
    litidx += idx_offset


    if litidx < 0
        while litidx < 0
            block -= 1
            litidx += read_uint16(tb, d.sizetable + 2 * block) + 1
        end
    else
        while litidx > read_uint16(tb, d.sizetable + 2 * block)
            litidx -= read_uint16(tb, d.sizetable + 2 * block) + 1
            block += 1
        end
    end


    ptr = d.data + (block << d.blocksize)

    m = d.min_len
    base_idx = -m
    symlen_idx = 0

    code = BigInt(read_uint64_be(tb, ptr))

    ptr += 2 * 4
    bitcnt = 0  # Number of empty bits in code
    local sym
    while true
        l = m
        while code < d.base[base_idx + l + 1]
            l += 1
        end
        sym = BigInt(read_uint16(tb, d.offset + l * 2))
        sym += (code - d.base[base_idx + l + 1]) >> (64 - l)
        if litidx < d.symlen[symlen_idx + sym + 1] + 1
            break
        end
        litidx -= d.symlen[symlen_idx + sym + 1] + 1
        code <<= l
        bitcnt += l
        if bitcnt >= 32
            bitcnt -= 32
            code |= BigInt(read_uint32_be(tb, ptr)) << bitcnt
            ptr += 4
        end
        # Cut off at 64bit.
        code &= 0xffffffffffffffff
    end

    sympat = d.sympat
    while d.symlen[symlen_idx + sym + 1] != 0
        w = sympat + 3 * sym
        s1 = ((read_byte(tb, w + 1) & Int(0xf)) << 8) | read_byte(tb, w) # ((tb.data[w + 1 + 1] & 0xf) << 8) | tb.data[w + 1]
        if litidx < d.symlen[symlen_idx + s1 + 1] + 1
            sym = s1
        else
            litidx -= d.symlen[symlen_idx + s1 + 1] + 1
            sym = (read_byte(tb, w + 2) << 4) | (read_byte(tb, w + 1) >> 4) #(tb.data[w + 2 + 1] << 4) | (tb.data[w + 1 + 1] >> 4)
        end
    end

    w = sympat + 3 * sym
    if tb.type == :dtz
        return ((read_byte(tb, w + 1) & Int(0x0f)) << 8) | read_byte(tb, w) # ((tb.data[w + 1 + 1] & 0x0f) << 8) | tb.data[w + 1]
    else
        return read_byte(tb, w) # tb.data[w + 1]
    end
end

function Base.close(tb::Table)
    if !ismissing(tb.fd)
        close(tb.fd)
        tb.fd = missing
    end
    tb.data = missing
end

function init_table_wdl(tb::Table)
    init_mmap(tb)
    @assert !ismissing(tb.data)

    if tb.initialized
        return
    end
    tb.type = :wdl

    check_magic(tb, b"q\xe8#]")

    tb.tb_size = zeros(Int, 8)
    tb.size = zeros(Int, 8 * 3)

    # Used if there are only pieces.
    tb.precomp = Dict{Int, PairsData}()
    tb.pieces = Dict{Int, Vector{Int}}()

    tb.factor = Dict{Int, Vector{Int}}(
        0 => zeros(Int, TBPIECES),
        1 => zeros(Int, TBPIECES)
    )

    tb.norm = Dict{Int, Vector{Int}}(
        0 => zeros(Int, tb.num),
        1 => zeros(Int, tb.num)
    )

    # Used if there are pawns.
    tb.files = [PawnFileData() for _ in 1:4]

    split = (read_byte(tb, 4) & Int(0x01)) != 0 # (tb.data[4 + 1] & 0x01) != 0
    files = (read_byte(tb, 4) & Int(0x02)) != 0 ? 4 : 1 # (tb.data[4 + 1] & 0x02) != 0 ? 4 : 1

    data_ptr = 5

    if !tb.has_pawns
        setup_pieces_piece(tb, data_ptr)
        data_ptr += tb.num + 1
        data_ptr += data_ptr & Int(0x01)

        tb.precomp[0] = setup_pairs(tb, data_ptr, tb.tb_size[0 + 1], 0, true)
        data_ptr = tb._next
        if split
            tb.precomp[1] = setup_pairs(tb, data_ptr, tb.tb_size[1 + 1], 3, true)
            data_ptr = tb._next
        end

        tb.precomp[0].indextable = data_ptr
        data_ptr += tb.size[0 + 1]
        if split
            tb.precomp[1].indextable = data_ptr
            data_ptr += tb.size[3 + 1]
        end

        tb.precomp[0].sizetable = data_ptr
        data_ptr += tb.size[1 + 1]
        if split
            tb.precomp[1].sizetable = data_ptr
            data_ptr += tb.size[4 + 1]
        end

        data_ptr = (data_ptr + Int(0x3f)) & ~Int(0x3f)
        tb.precomp[0].data = data_ptr
        data_ptr += tb.size[2 + 1]
        if split
            data_ptr = (data_ptr + Int(0x3f)) & ~Int(0x3f)
            tb.precomp[1].data = data_ptr
        end

        tb.key = recalc_key(tb.pieces[0])
        tb.mirrored_key = recalc_key(tb.pieces[0], mirror=true)
    else
        s = 1 + Int(tb.pawns[1] > 0)
        for f in 0:3#range(4):
            setup_pieces_pawn(tb, data_ptr, 2 * f, f)
            data_ptr += tb.num + s
        end
        data_ptr += data_ptr & Int(0x01)

        for f in 0:(files-1)#range(files):
            tb.files[f + 1].precomp[0] = setup_pairs(tb, data_ptr, tb.tb_size[2 * f + 1], 6 * f, true)
            data_ptr = tb._next
            if split
                tb.files[f + 1].precomp[1] = setup_pairs(tb, data_ptr, tb.tb_size[2 * f + 1 + 1], 6 * f + 3, true)
                data_ptr = tb._next
            end
        end

        for f in 0:(files-1)#range(files):
            tb.files[f + 1].precomp[0].indextable = data_ptr
            data_ptr += tb.size[6 * f + 1]
            if split
                tb.files[f + 1].precomp[1].indextable = data_ptr
                data_ptr += tb.size[6 * f + 3 + 1]
            end
        end

        for f in 0:(files-1)#range(files):
            tb.files[f + 1].precomp[0].sizetable = data_ptr
            data_ptr += tb.size[6 * f + 1 + 1]
            if split
                tb.files[f + 1].precomp[1].sizetable = data_ptr
                data_ptr += tb.size[6 * f + 4 + 1]
            end
        end

        for f in 0:(files-1)#range(files):
            data_ptr = (data_ptr + Int(0x3f)) & ~Int(0x3f)
            tb.files[f + 1].precomp[0].data = data_ptr
            data_ptr += tb.size[6 * f + 2 + 1]
            if split
                data_ptr = (data_ptr + Int(0x3f)) & ~Int(0x3f)
                tb.files[f + 1].precomp[1].data = data_ptr
                data_ptr += tb.size[6 * f + 5 + 1]
            end
        end
    end

    tb.initialized = true
end

function setup_pieces_pawn(tb::Table, p_data::Int, p_tb_size::Int, f::Int)
    @assert !ismissing(tb.data)
    @assert tb.type == :wdl

    j = 1 + Int(tb.pawns[1] > 0)
    order = read_byte(tb, p_data) & Int(0x0f)#tb.data[p_data + 1] & 0x0f
    order2 = tb.pawns[1] != 0 ? read_byte(tb, p_data + 1) & Int(0x0f) : Int(0x0f) #tb.pawns[1] != 0 ? tb.data[p_data + 1 + 1] & 0x0f : 0x0f
    tb.files[f + 1].pieces[0] = [read_byte(tb, p_data + i + j) & Int(0x0f) for i in 0:(tb.num-1)] # [tb.data[p_data + i + j + 1] & 0x0f for i in 0:(tb.num-1)]
    tb.files[f + 1].norm[0] = zeros(Int, tb.num)
    set_norm_pawn(tb, tb.files[f + 1].norm[0], tb.files[f + 1].pieces[0])
    tb.files[f + 1].factor[0] = zeros(Int, TBPIECES)
    tb.tb_size[p_tb_size + 1] = calc_factors_pawn(tb, tb.files[f + 1].factor[0], order, order2, tb.files[f + 1].norm[0], f)

    order = read_byte(tb, p_data) >> 4 # tb.data[p_data + 1] >> 4
    order2 = tb.pawns[1] != 0 ? read_byte(tb, p_data + 1) >> 4 : Int(0x0f) # tb.pawns[1] != 0 ? tb.data[p_data + 1 + 1] >> 4 : 0x0f
    tb.files[f + 1].pieces[1] = [read_byte(tb, p_data + i + j) >> 4 for i in 0:(tb.num-1)] # [tb.data[p_data + i + j + 1] >> 4 for i in 0:(tb.num-1)]
    tb.files[f + 1].norm[1] = zeros(Int, tb.num)
    set_norm_pawn(tb, tb.files[f + 1].norm[1], tb.files[f + 1].pieces[1])
    tb.files[f + 1].factor[1] = zeros(Int, TBPIECES)
    tb.tb_size[p_tb_size + 1 + 1] = calc_factors_pawn(tb, tb.files[f + 1].factor[1], order, order2, tb.files[f + 1].norm[1], f)
end

function setup_pieces_piece(tb::Table, p_data::Int)
    @assert !ismissing(tb.data)
    @assert tb.type == :wdl

    tb.pieces[0] = [read_byte(tb, p_data + i + 1) & Int(0x0f) for i in 0:(tb.num-1)] # [tb.data[p_data + i + 1 + 1] & 0x0f for i in 0:(tb.num-1)]
    order = read_byte(tb, p_data) & Int(0x0f) # tb.data[p_data + 1] & 0x0f
    set_norm_piece(tb, tb.norm[0], tb.pieces[0])
    tb.tb_size[0 + 1] = calc_factors_piece(tb, tb.factor[0], order, tb.norm[0])

    tb.pieces[1] = [read_byte(tb, p_data + i + 1) >> 4 for i in 0:(tb.num-1)] # [tb.data[p_data + i + 1 + 1] >> 4 for i in 0:(tb.num-1)]
    order = read_byte(tb, p_data) >> 4 # tb.data[p_data + 1] >> 4
    set_norm_piece(tb, tb.norm[1], tb.pieces[1])
    tb.tb_size[1 + 1] = calc_factors_piece(tb, tb.factor[1], order, tb.norm[1])
end

function probe_wdl_table(tb::Table, board::Board)::Int
    tb.read_count += 1
    return _probe_wdl_table(tb, board)
end

function _probe_wdl_table(tb::Table, board::Board)::Int
    init_table_wdl(tb)
    @assert tb.type == :wdl

    key = calc_key(board)

    if !tb.symmetric
        if key != tb.key
            cmirror = 8
            mirror = Int(0x38)
            bside = Int(sidetomove(board) == WHITE)
        else
            cmirror = mirror = 0
            bside = Int(sidetomove(board) != WHITE)
        end
    else
        cmirror = sidetomove(board) == WHITE ? 0 : 8
        mirror = sidetomove(board) == WHITE ? 0 : Int(0x38)
        bside = 0
    end

    if !tb.has_pawns
        p = zeros(Int, TBPIECES)
        i = 0
        while i < tb.num
            piece_type = PieceType(tb.pieces[bside][i + 1] & Int(0x07))
            color = (tb.pieces[bside][i + 1] ⊻ cmirror) >> 3
            #bb = board.pieces_mask(piece_type, chess.WHITE if color == 0 else chess.BLACK)
            bb = pieces(board, color == 0 ? WHITE : BLACK, piece_type)

            for square in bb
                p[i + 1] = SQTOPOS[square.val]
                i += 1
            end
        end

        idx = encode_piece(tb, tb.norm[bside], p, tb.factor[bside])
        res = decompress_pairs(tb, tb.precomp[bside], idx)
    else
        p = zeros(Int, TBPIECES)
        i = 0
        k = tb.files[0 + 1].pieces[0][0 + 1] ⊻ cmirror
        color = k >> 3
        piece_type = PieceType(k & Int(0x07))
        #bb = board.pieces_mask(piece_type, chess.WHITE if color == 0 else chess.BLACK)
        bb = pieces(board, color == 0 ? WHITE : BLACK, piece_type)

        for square in bb
            p[i + 1] = SQTOPOS[square.val] ⊻ mirror
            i += 1
        end

        f = pawn_file(tb, p)
        pc = tb.files[f + 1].pieces[bside]
        while i < tb.num
            color = (pc[i + 1] ⊻ cmirror) >> 3
            piece_type = PieceType(pc[i + 1] & Int(0x07))
            #bb = board.pieces_mask(piece_type, chess.WHITE if color == 0 else chess.BLACK)
            bb = pieces(board, color == 0 ? WHITE : BLACK, piece_type)

            for square in bb
                p[i + 1] = SQTOPOS[square.val] ⊻ mirror
                i += 1
            end
        end

        idx = encode_pawn(tb, tb.files[f + 1].norm[bside], p, tb.files[f + 1].factor[bside])
        res = decompress_pairs(tb, tb.files[f + 1].precomp[bside], idx)
    end

    return res - 2
end


function init_table_dtz(tb::Table)
    init_mmap(tb)
    @assert !ismissing(tb.data)

    if tb.initialized
        return
    end
    tb.type = :dtz

    check_magic(tb, b"\xd7f\x0c\xa5")

    tb.dtz_factor = zeros(Int, TBPIECES)
    tb.dtz_norm = zeros(Int, tb.num)
    tb.tb_size = zeros(Int, 4)
    tb.size = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    tb.dtz_files = [PawnFileDataDtz() for f in 1:4]

    files = (read_byte(tb, 4) & Int(0x02)) != 0 ? 4 : 1 #  (tb.data[4 + 1] & 0x02) != 0 ? 4 : 1

    p_data = 5

    if !tb.has_pawns
        tb.map_idx = [[0, 0, 0, 0]]

        setup_pieces_piece_dtz(tb, p_data, 0)
        p_data += tb.num + 1
        p_data += p_data & Int(0x01)

        tb.dtz_precomp = setup_pairs(tb, p_data, tb.tb_size[0 + 1], 0, false)
        tb.dtz_flags = tb._flags
        p_data = tb._next
        tb.p_map = p_data
        if (tb.dtz_flags & 2) != 0
            if (tb.dtz_flags & 16) == 0
                for i in 0:3#range(4):
                    tb.map_idx[0 + 1][i + 1] = p_data + 1 - tb.p_map
                    p_data += 1 + read_byte(tb, p_data) # 1 + tb.data[p_data + 1]
                end
            else
                for i in 0:3#range(4):
                    tb.map_idx[0 + 1][i + 1] = (p_data + 2 - tb.p_map) ÷ 2
                    p_data += 2 + 2 * read_uint16(tb, p_data)
                end
            end
        end

        p_data += p_data & Int(0x01)

        tb.dtz_precomp.indextable = p_data
        p_data += tb.size[0 + 1]

        tb.dtz_precomp.sizetable = p_data
        p_data += tb.size[1 + 1]

        p_data = (p_data + Int(0x3f)) & ~Int(0x3f)
        tb.dtz_precomp.data = p_data
        p_data += tb.size[2 + 1]

        tb.key = recalc_key(tb.dtz_pieces)
        tb.mirrored_key = recalc_key(tb.dtz_pieces, mirror=true)
    else
        s = 1 + Int(tb.pawns[1] > 0)
        for f in 0:3#range(4):
            setup_pieces_pawn_dtz(tb, p_data, f, f)
            p_data += tb.num + s
        end
        p_data += p_data & Int(0x01)

        tb.dtz_flags = Int[]
        for f in 0:(files-1)#range(files):
            tb.dtz_files[f + 1].precomp = setup_pairs(tb, p_data, tb.tb_size[f + 1], 3 * f, false)
            p_data = tb._next
            push!(tb.dtz_flags, tb._flags)
        end

        tb.map_idx = []
        tb.p_map = p_data
        for f in 0:(files-1)#range(files):
            push!(tb.map_idx, [])
            if (tb.dtz_flags[f + 1] & 2) != 0
                if (tb.dtz_flags[f + 1] & 16) == 0
                    for _ in 0:3#range(4):
                        push!(tb.map_idx[end], p_data + 1 - tb.p_map)
                        p_data += 1 + read_byte(tb, p_data) # 1 + tb.data[p_data + 1]
                    end
                else
                    p_data += p_data & Int(0x01)
                    for _ in 0:3#range(4):
                        push!(tb.map_idx[end], (p_data + 2 - tb.p_map) ÷ 2)
                        p_data += 2 + 2 * read_uint16(tb, p_data)
                    end
                end
            end
        end
        p_data += p_data & Int(0x01)

        for f in 0:(files-1)#range(files):
            tb.dtz_files[f + 1].precomp.indextable = p_data
            p_data += tb.size[3 * f + 1]
        end

        for f in 0:(files-1)#range(files):
            tb.dtz_files[f + 1].precomp.sizetable = p_data
            p_data += tb.size[3 * f + 1 + 1]
        end

        for f in 0:(files-1)#range(files):
            p_data = (p_data + Int(0x3f)) & ~Int(0x3f)
            tb.dtz_files[f + 1].precomp.data = p_data
            p_data += tb.size[3 * f + 2 + 1]
        end
    end

    tb.initialized = true
end

function probe_dtz_table(tb::Table, board::Board, wdl::Int)::Tuple{Int, Int}
    tb.read_count += 1
    return _probe_dtz_table(tb, board, wdl)
end

function _probe_dtz_table(tb::Table, board::Board, wdl::Int)::Tuple{Int, Int}
    init_table_dtz(tb)
    @assert !ismissing(tb.data)
    @assert tb.type == :dtz

    key = calc_key(board)

    if !tb.symmetric
        if key != tb.key
            cmirror = 8
            mirror = 0x38
            bside = Int(sidetomove(board) == WHITE)
        else
            cmirror = 0
            mirror = 0
            bside = Int(sidetomove(board) != WHITE)
        end
    else
        cmirror = sidetomove(board) == WHITE ? 0 : 8
        mirror = sidetomove(board) == WHITE ? 0 : Int(0x38)
        bside = 0
    end

    if !tb.has_pawns
        @assert tb.dtz_flags isa Int

        if (tb.dtz_flags & 1) != bside && !tb.symmetric
            return 0, -1
        end

        pc = tb.dtz_pieces
        p = zeros(Int, TBPIECES)
        i = 0
        while i < tb.num
            piece_type = PieceType(pc[i + 1] & Int(0x07))
            color = (pc[i + 1] ⊻ cmirror) >> 3
            #bb = board.pieces_mask(piece_type, chess.WHITE if color == 0 else chess.BLACK)
            bb = pieces(board, color == 0 ? WHITE : BLACK, piece_type)

            for square in bb
                p[i + 1] = SQTOPOS[square.val]
                i += 1
            end
        end


        idx = encode_piece(tb, tb.dtz_norm, p, tb.dtz_factor)
        res = decompress_pairs(tb, tb.dtz_precomp, idx)

        if (tb.dtz_flags & 2) != 0
            if (tb.dtz_flags & 16) == 0
                res = read_byte(tb, tb.p_map + tb.map_idx[0 + 1][WDL_TO_MAP[wdl + 2 + 1] + 1] + res) # tb.data[tb.p_map + tb.map_idx[0 + 1][WDL_TO_MAP[wdl + 2 + 1] + 1] + res + 1]
            else
                res = read_uint16(tb, tb.p_map + 2 * (tb.map_idx[0 + 1][WDL_TO_MAP[wdl + 2 + 1] + 1] + res))
            end
        end

        if ((tb.dtz_flags & PA_FLAGS[wdl + 2 + 1]) == 0) || ((wdl & 1) != 0)
            res *= 2
        end
    else
        @assert tb.dtz_flags isa Vector

        k = tb.dtz_files[0 + 1].pieces[0 + 1] ⊻ cmirror
        piece_type = PieceType(k & Int(0x07))
        color = k >> 3
        #bb = board.pieces_mask(piece_type, chess.WHITE if color == 0 else chess.BLACK)
        bb = pieces(board, color == 0 ? WHITE : BLACK, piece_type)

        i = 0
        p = zeros(Int, TBPIECES)
        for square in bb
            p[i + 1] = SQTOPOS[square.val] ⊻ mirror
            i += 1
        end
        f = pawn_file(tb, p)
        if tb.dtz_flags[f + 1] & 1 != bside
            return 0, -1
        end

        pc = tb.dtz_files[f + 1].pieces
        while i < tb.num
            piece_type = PieceType(pc[i + 1] & Int(0x07))
            color = (pc[i + 1] ⊻ cmirror) >> 3
            #bb = board.pieces_mask(piece_type, chess.WHITE if color == 0 else chess.BLACK)
            bb = pieces(board, color == 0 ? WHITE : BLACK, piece_type)

            for square in bb
                p[i + 1] = SQTOPOS[square.val] ⊻ mirror
                i += 1
            end
        end

        idx = encode_pawn(tb, tb.dtz_files[f + 1].norm, p, tb.dtz_files[f + 1].factor)
        res = decompress_pairs(tb, tb.dtz_files[f + 1].precomp, idx)

        if (tb.dtz_flags[f + 1] & 2) != 0
            if (tb.dtz_flags[f + 1] & 16) == 0
                res = read_byte(tb, tb.p_map + tb.map_idx[f + 1][WDL_TO_MAP[wdl + 2 + 1] + 1] + res) #  tb.data[tb.p_map + tb.map_idx[f + 1][WDL_TO_MAP[wdl + 2 + 1] + 1] + res + 1]
            else
                res = read_uint16(tb, tb.p_map + 2 * (tb.map_idx[f + 1][WDL_TO_MAP[wdl + 2 + 1] + 1] + res))
            end
        end

        if ((tb.dtz_flags[f + 1] & PA_FLAGS[wdl + 2 + 1]) == 0) || ((wdl & 1) != 0)
            res *= 2
        end
    end

    return res, 1
end

function setup_pieces_piece_dtz(tb::Table, p_data::Int, p_tb_size::Int)
    @assert !ismissing(tb.data)
    @assert tb.type == :dtz

    tb.dtz_pieces = [read_byte(tb, p_data + i + 1) & Int(0x0f) for i in 0:(tb.num-1)] # [tb.data[p_data + i + 1 + 1] & 0x0f for i in 0:(length(tb.num)-1)]
    order = read_byte(tb, p_data) & Int(0x0f) # tb.data[p_data + 1] & 0x0f
    set_norm_piece(tb, tb.dtz_norm, tb.dtz_pieces)
    tb.tb_size[p_tb_size + 1] = calc_factors_piece(tb, tb.dtz_factor, order, tb.dtz_norm)
end

function setup_pieces_pawn_dtz(tb::Table, p_data::Int, p_tb_size::Int, f::Int)
    @assert !ismissing(tb.data)
    @assert tb.type == :dtz

    j = 1 + Int(tb.pawns[1] > 0)
    order = read_byte(tb, p_data) & Int(0x0f) # tb.data[p_data + 1] & 0x0f
    order2 = tb.pawns[1] != 0 ? read_byte(tb, p_data + 1) & Int(0x0f) : Int(0x0f) # tb.pawns[1] != 0 ? tb.data[p_data + 1 + 1] & 0x0f : 0x0f
    tb.dtz_files[f + 1].pieces = [read_byte(tb, p_data + i + j) & Int(0x0f) for i in 0:(tb.num - 1)] # [tb.data[p_data + i + j + 1] & 0x0f for i in 0:(length(tb.num) - 1)]

    tb.dtz_files[f + 1].norm = zeros(Int, tb.num)
    set_norm_pawn(tb, tb.dtz_files[f + 1].norm, tb.dtz_files[f + 1].pieces)

    tb.dtz_files[f + 1].factor = zeros(Int, TBPIECES)
    tb.tb_size[p_tb_size + 1] = calc_factors_pawn(tb, tb.dtz_files[f + 1].factor, order, order2, tb.dtz_files[f + 1].norm, f)
end



mutable struct Tablebase
    max_fds::Int
    lru::Vector{Table}
    wdl::Dict{String, Table}
    dtz::Dict{String, Table}

    """
    Manages a collection of tablebase files for probing.
    If *max_fds* is not ``0``, will at most use *max_fds* open file
    descriptors at any given time. The least recently used tables are closed,
    if nescessary.
    """
    function Tablebase(;max_fds::Int = 128)
        self = new()
        self.max_fds = max_fds
        self.lru = Vector{Table}()

        self.wdl = Dict{String, Table}()
        self.dtz = Dict{String, Table}()
        return self
    end
end

function _bump_lru(self::Tablebase, table::Table)
    if self.max_fds == 0
        return
    end

    i = 0
    for (j, othertable) in enumerate(self.lru)
        if table == othertable
            i = j
            break
        end
    end

    if i != 0
        popat!(self.lru, i)
    end

    pushfirst!(self.lru, table)

    if length(self.lru) > self.max_fds
        close(pop!(self.lru))
    end
end

function _open_table(self::Tablebase, hashtable::Dict{String,Table}, path::String)::Int
    table = Table(path)

    if haskey(hashtable, table.key)
        close(hashtable[table.key])
    end

    hashtable[table.key] = table
    hashtable[table.mirrored_key] = table
    return 1
end

function add_directory(self::Tablebase, directory::String; load_wdl::Bool=true, load_dtz::Bool=true)::Int
    """
    Adds tables from a directory.
    By default all available tables with the correct file names
    (e.g. WDL files like ``KQvKN.rtbw`` and DTZ files like ``KRBvK.rtbz``)
    are added.
    The relevant files are lazily opened when the tablebase is actually
    probed.
    Returns the number of table files that were found.
    """
    num = 0
    directory = abspath(directory)

    for filename in readdir(directory)
        path = joinpath(directory, filename)
        tablename, ext = splitext(filename)

        if is_tablename(tablename) && isfile(path)
            if load_wdl
                if ext == ".rtbw"
                    num += _open_table(self, self.wdl, path)
                end
            end

            if load_dtz
                if ext == ".rtbz"
                    num += _open_table(self, self.dtz, path)
                end
            end
        end
    end
    return num
end

function probe_wdl_table(self::Tablebase, board::Board)::Int

    # Test for KvK.
    if kings(board) == occupiedsquares(board)
        return 0
    end

    key = calc_key(board)
    local table
    try
        table = self.wdl[key]
    catch KeyError
        error("did not find wdl table $key")
    end

    _bump_lru(self, table)

    return probe_wdl_table(table, board)
end

function probe_ab(self::Tablebase, board::Board, alpha::Int, beta::Int; threats::Bool=false)::Tuple{Int, Int}

    # Generate non-ep captures.
    for move in moves(board)# board.generate_legal_moves(to_mask=board.occupied_co[not board.turn]):
        if !moveiscapture(board, move) || moveisep(board, move)
            continue
        end

        undoinfo = domove!(board, move)

        v_plus, _ = probe_ab(self, board, -beta, -alpha)
        v = -v_plus

        undomove!(board, undoinfo)

        if v > alpha
            if v >= beta
                return v, 2
            end
            alpha = v
        end
    end

    v = probe_wdl_table(self, board)

    if alpha >= v
        return alpha, 1 + Int(alpha > 0)
    else
        return v, 1
    end
end

function sprobe_ab(self::Tablebase, board::Board, alpha::Int, beta::Int; threats::Bool=false)::Tuple{Int, Int}
    # chess.popcount(board.occupied_co[not board.turn]) > 1:
    if squarecount(pieces(board, sidetomove(board) == WHITE ? BLACK : WHITE)) > 1
        v, captures_found = sprobe_capts(self, board, alpha, beta)
        if captures_found
            return v, 2
        end
    else
        #any(board.generate_legal_captures()):
        if any(m->moveiscapture(board, m), moves(board))
            return -2, 2
        end
    end

    threats_found = false

    if threats || squarecount(occupiedsquares(board)) >= 6 # chess.popcount(board.occupied) >= 6:
        for threat in moves(board) # board.generate_legal_moves(~board.pawns): # from mask
            if from(threat) in pawns(board)
                continue
            end
            undoinfo = domove!(board, threat)
            v_plus, captures_found = sprobe_capts(self, board, -beta, -alpha)
            v = -v_plus

            undomove!(board, undoinfo)

            if captures_found && v > alpha
                threats_found = true
                alpha = v
                if alpha >= beta
                    return v, 3
                end
            end
        end
    end

    v = probe_wdl_table(self, board)
    if v > alpha
        return v, 1
    else
        return alpha, threats_found ? 3 : 1
    end
end

function sprobe_capts(self::Tablebase, board::Board, alpha::Int, beta::Int)::Tuple{Int, Int}
    captures_found = false

    for move in moves(board)#board.generate_legal_captures():
        if !moveiscapture(board, move)
            continue
        end
        captures_found = true

        undoinfo = domove!(board, move)

        v_plus, _ = sprobe_ab(self, board, -beta, -alpha)
        v = -v_plus

        undomove!(board, undoinfo)

        alpha = max(v, alpha)

        if alpha >= beta
            break
        end
    end

    return alpha, captures_found
end

function probe_wdl(self::Tablebase, board::Board)::Int
    """
    Probes WDL tables for win/draw/loss-information.
    Probing is thread-safe when done with different *board* objects and
    if *board* objects are not modified during probing.
    Returns ``2`` if the side to move is winning, ``0`` if the position is
    a draw and ``-2`` if the side to move is losing.
    Returns ``1`` in case of a cursed win and ``-1`` in case of a blessed
    loss. Mate can be forced but the position can be drawn due to the
    fifty-move rule.
    """
    # Positions with castling rights are not in the tablebase.
    if cancastle(board)
        error("syzygy tables do not contain positions with castling rights: $(fen(board))")
    end

    # Validate piece count.
    popcount = squarecount(occupiedsquares(board))
    if popcount > TBPIECES
        error("syzygy tables support up to $(TBPIECES) pieces, not $(popcount): $(fen(board))")
    end

    # Probe.
    v, _ = probe_ab(self, board, -2, 2)

    # If en passant is not possible, we are done.
    if epsquare(board) == SQ_NONE
        return v
    end

    # Now handle en passant.
    v1 = -3

    # Look at all legal en passant captures.
    ep_moves = MoveList(16)
    Chess.genep(board, ep_moves)
    for move in ep_moves
        undoinfo = domove!(board, move)
        v0_plus, _ = probe_ab(self, board, -2, 2)
        v0 = -v0_plus

        undomove!(board, undoinfo)

        if v0 > v1
            v1 = v0
        end
    end

    if v1 > -3
        if v1 >= v
            v = v1
        elseif v == 0
            # If there is not at least one legal non-en-passant move we are
            # forced to play the losing en passant cature.
            #if all(board.is_en_passant(move) for move in board.generate_legal_moves()):
            if length(ep_moves) == length(moves(board))
                v = v1
            end
        end
    end

    return v
end

function get_wdl(self::Tablebase, board::Board, default=nothing)
    try
        return probe_wdl(self, board)
    catch
        return default
    end
end

function probe_dtz_table(self::Tablebase, board::Board, wdl::Int)::Tuple{Int, Int}
    key = calc_key(board)
    local table
    try
        table = self.dtz[key]
    catch KeyError
        error("did not find dtz table $key")
    end

    _bump_lru(self, table)

    return probe_dtz_table(table, board, wdl)
end

function probe_dtz_no_ep(self::Tablebase, board::Board)::Int
    wdl, success = probe_ab(self, board, -2, 2, threats=true)

    if wdl == 0
        return 0
    end

    #if success == 2 or not board.occupied_co[board.turn] & ~board.pawns:
    if success == 2 || (pieces(board, sidetomove(board)) - pawns(board)) == SS_EMPTY
        return dtz_before_zeroing(wdl)
    end

    if wdl > 0
        # The position is a win or a cursed win by a threat move.
        if success == 3
            return wdl == 2 ? 2 : 102
        end

        # Generate all legal non-capturing pawn moves.
        for move in moves(board)#board.generate_legal_moves(board.pawns, ~board.occupied):
            if !(from(move) in pawns(board)) || moveiscapture(board, move) # checks en passant
                continue
            end

            undoinfo = domove!(board, move)

            v = -probe_wdl(self, board)

            undomove!(board, undoinfo)

            if v == wdl
                return v == 2 ? 1 : 101
            end
        end
    end

    dtz, success = probe_dtz_table(self, board, wdl)
    if success >= 0
        return dtz_before_zeroing(wdl) + (wdl > 0 ? dtz : -dtz)
    end

    if wdl > 0
        best = Int(0xffff)

        #board.generate_legal_moves(~board.pawns, ~board.occupied):
        for move in moves(board)
            if from(move) in pawns(board) || to(move) in occupiedsquares(board)
                continue
            end

            undoinfo = domove!(board, move)
            v = -probe_dtz(self, board)

            if v == 1 && ischeckmate(board)
                best = 1
            elseif v > 0 && v + 1 < best
                best = v + 1
            end

            undomove!(board, undoinfo)
        end

        return best
    else
        best = -1

        for move in moves(board)
            undoinfo = domove!(board, move)

            if board.r50 == 0
                if wdl == -2
                    v = -1
                else
                    v, success = probe_ab(self, board, 1, 2, threats=true)
                    v = v == 2 ? 0 : -101
                end
            else
                v = -probe_dtz(self, board) - 1
            end

            undomove!(board, undoinfo)

            if v < best
                best = v
            end
        end

        return best
    end
end

function probe_dtz(self::Tablebase, board::Board)::Int
    """
    Probes DTZ tables for distance to zero information.
    Both DTZ and WDL tables are required in order to probe for DTZ.
    Returns a positive value if the side to move is winning, ``0`` if the
    position is a draw and a negative value if the side to move is losing.
    More precisely:
    +-----+------------------+--------------------------------------------+
    | WDL | DTZ              |                                            |
    +=====+==================+============================================+
    |  -2 | -100 <= n <= -1  | Unconditional loss (assuming 50-move       |
    |     |                  | counter is zero), where a zeroing move can |
    |     |                  | be forced in -n plies.                     |
    +-----+------------------+--------------------------------------------+
    |  -1 |         n < -100 | Loss, but draw under the 50-move rule.     |
    |     |                  | A zeroing move can be forced in -n plies   |
    |     |                  | or -n - 100 plies (if a later phase is     |
    |     |                  | responsible for the blessed loss).         |
    +-----+------------------+--------------------------------------------+
    |   0 |         0        | Draw.                                      |
    +-----+------------------+--------------------------------------------+
    |   1 |   100 < n        | Win, but draw under the 50-move rule.      |
    |     |                  | A zeroing move can be forced in n plies or |
    |     |                  | n - 100 plies (if a later phase is         |
    |     |                  | responsible for the cursed win).           |
    +-----+------------------+--------------------------------------------+
    |   2 |    1 <= n <= 100 | Unconditional win (assuming 50-move        |
    |     |                  | counter is zero), where a zeroing move can |
    |     |                  | be forced in n plies.                      |
    +-----+------------------+--------------------------------------------+
    The return value can be off by one: a return value -n can mean a
    losing zeroing move in in n + 1 plies and a return value +n can mean a
    winning zeroing move in n + 1 plies.
    This is guaranteed not to happen for positions exactly on the edge of
    the 50-move rule, so that (with some care) this never impacts the
    result of practical play.
    Minmaxing the DTZ values guarantees winning a won position (and drawing
    a drawn position), because it makes progress keeping the win in hand.
    However the lines are not always the most straightforward ways to win.
    Engines like Stockfish calculate themselves, checking with DTZ, but
    only play according to DTZ if they can not manage on their own.
    """
    v = probe_dtz_no_ep(self, board)

    if epsquare(board) == SQ_NONE
        return v
    end

    v1 = -3

    # Generate all en passant moves.
    ep_moves = MoveList(16)
    Chess.genep(board, ep_moves)
    for move in ep_moves
        undoinfo = domove!(board, move)

        v0_plus, _ = probe_ab(self, board, -2, 2)
        v0 = -v0_plus

        undomove!(board, undoinfo)

        if v0 > v1
            v1 = v0
        end
    end

    if v1 > -3
        v1 = WDL_TO_DTZ[v1 + 2 + 1]
        if v < -100
            if v1 >= 0
                v = v1
            end
        elseif v < 0
            if v1 >= 0 || v1 < -100
                v = v1
            end
        elseif v > 100
            if v1 > 0
                v = v1
            end
        elseif v > 0
            if v1 == 1
                v = v1
            end
        elseif v1 >= 0
            v = v1
        else
            #if all(board.is_en_passant(move) for move in board.generate_legal_moves()):
            if length(ep_moves) == length(moves(board))
                v = v1
            end
        end
    end

    return v
end

function get_dtz(self::Tablebase, board::Board, default=nothing)
    try
        return probe_dtz(self, board)
    catch
        return default
    end
end

function Base.close(self::Tablebase)
    """Closes all loaded tables."""
    for (key, tb) in self.wdl
        close(tb)
    end
    for (key, tb) in self.dtz
        close(tb)
    end

    empty!(self.wdl)
    empty!(self.dtz)
    empty!(self.lru)
end


function open_tablebase(directory::String; load_wdl::Bool=true, load_dtz::Bool=true, max_fds::Int=128)::Tablebase
    """
    Opens a collection of tables for probing. See
    :class:`~chess.syzygy.Tablebase`.
    .. note::
        Generally probing requires tablebase files for the specific
        material composition, **as well as** material compositions transitively
        reachable by captures and promotions.
        This is important because 6-piece and 5-piece (let alone 7-piece) files
        are often distributed separately, but are both required for 6-piece
        positions. Use :func:`~chess.syzygy.Tablebase.add_directory()` to load
        tables from additional directories.
    """
    tables = Tablebase(max_fds=max_fds)
    add_directory(tables, directory, load_wdl=load_wdl, load_dtz=load_dtz)
    return tables
end


function Base.show(io::IO, tables::Tablebase)
    print(io, "Tablebase object")
end


end # module
