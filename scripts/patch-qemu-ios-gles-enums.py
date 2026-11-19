#!/usr/bin/env python3
"""Define desktop/ES extension enums missing from Apple's ES 1.1 headers."""
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
marker = "#define GLES_BGRA_READ_TYPE"
block = """
/* Tokens used by the shared validation/readback code but not declared by
 * Apple's OpenGL ES 1.1 headers. These are specification enum values only;
 * they do not imply that the ES 1.1 device supports every operation. */
#ifndef GL_UNPACK_ROW_LENGTH
#define GL_UNPACK_ROW_LENGTH 0x0CF2
#endif
#ifndef GL_TEXTURE_CUBE_MAP
#define GL_TEXTURE_CUBE_MAP 0x8513
#endif
#ifndef GL_TEXTURE_CUBE_MAP_POSITIVE_X
#define GL_TEXTURE_CUBE_MAP_POSITIVE_X 0x8515
#endif
#ifndef GL_TEXTURE_CUBE_MAP_NEGATIVE_Z
#define GL_TEXTURE_CUBE_MAP_NEGATIVE_Z 0x851A
#endif
#ifndef GL_RED
#define GL_RED 0x1903
#endif
#ifndef GL_DEPTH_COMPONENT
#define GL_DEPTH_COMPONENT 0x1902
#endif
#ifndef GL_UNSIGNED_INT_8_8_8_8
#define GL_UNSIGNED_INT_8_8_8_8 0x8035
#endif
#ifndef GL_UNSIGNED_INT_8_8_8_8_REV
#define GL_UNSIGNED_INT_8_8_8_8_REV 0x8367
#endif
#ifndef GL_MAX_ELEMENTS_VERTICES
#define GL_MAX_ELEMENTS_VERTICES 0x80E8
#endif
#ifndef GL_MAX_ELEMENTS_INDICES
#define GL_MAX_ELEMENTS_INDICES 0x80E9
#endif

"""
if "GL_TEXTURE_CUBE_MAP_POSITIVE_X" in s and "GL_UNPACK_ROW_LENGTH" in s:
    print("OpenGL ES compatibility enum definitions already present")
    raise SystemExit(0)
if marker not in s:
    raise SystemExit(f"Could not find insertion point in {p}")
p.write_text(s.replace(marker, block + marker, 1))
print(f"Patched missing OpenGL ES enum definitions in {p}")
