"""Compile the patched decoder and query setup against offline C fixtures.

Usage: python3 test_patch.py /path/to/patched/linux
No firmware access; the allocation shim deliberately poisons kmalloc memory.
"""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]) / "drivers/platform/x86/hp/hp-bioscfg"
text = (source / "bioscfg.c").read_text()
start = text.index("int hp_convert_hexstr_to_str(")
decoder = text[start:text.index("\n}\n", start) + 3]
text = (source / "biosattr-interface.c").read_text()
start = text.index("\tbios_args_size = struct_size(args, data,")
setup = text[start:text.index("\n\tret = wmi_evaluate_method", start)]
shim = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
typedef uint32_t u32;
#define GFP_KERNEL 0
#define kzalloc(n, f) calloc(1, n)
#define kfree free
#define max_t(t, a, b) ((t)(a) > (t)(b) ? (t)(a) : (t)(b))
#define struct_size(p, field, n) (sizeof(*(p)) + (n))
#define flex_array_size(p, field, n) (n)
static int hex_to_bin(unsigned char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
'''
fixtures = r'''
static void decode(const char *in, unsigned n, const char *expected) {
    char *out = NULL; int len = -1;
    int rc = hp_convert_hexstr_to_str(in, n, &out, &len);
    if (!expected) { assert(rc < 0); assert(out == NULL); return; }
    assert(rc == 0); if (strcmp(out, expected)) { fprintf(stderr, "Mismatch for %.*s: [%s] != [%s]\n", n, in, out, expected); abort(); }
    assert(len == (int)strlen(expected)); free(out);
}
struct bios_args { u32 signature, command, commandtype, datasize; char data[]; };
static int query(unsigned insize) {
    unsigned char buffer[256];
    struct bios_args *args = NULL;
    struct { size_t length; void *pointer; } input;
    size_t bios_args_size;
    int command = 1, query = 2;
    memset(buffer, 0xa5, sizeof(buffer));
'''
checks = r'''
    assert(input.pointer == args);
    assert(input.length == 16 + (insize > 128 ? insize : 128));
    assert(args->datasize == insize);
    assert(args->signature == 0x55434553);
    assert(args->command == 1 && args->commandtype == 2);
    assert(!memcmp(args->data, buffer, insize));
    for (unsigned i = insize; i < input.length - 16; i++) assert(args->data[i] == 0);
    free(args); return 0;
}
int main(void) {
    decode("After Power Loss", 16, "After Power Loss");
    decode("Virtualization Technology (VTx/VTd)", 35, "Virtualization Technology (VTx/VTd)");
    decode("BIOS Update", 11, "BIOS Update");
    decode("0x00", 4, "");
    decode("0x4f 0x6e 0x00", 14, "On");
    decode("0x00 0x41", 9, NULL);
    decode("0x4f 0x6e", 9, "On");
    decode("0x4f 0x6e ", 10, "On");
    decode("0x5c 0x0a 0x09", 14, "\\\\\\n\\t");
    const char bounded[] = {'O', 'n'};
    decode(bounded, 2, "On");
    decode("0x", 2, NULL); decode("0xGG", 4, NULL);
    decode("0x4fX", 5, NULL); decode("0x4f 0x", 7, NULL);
    decode("A\0B", 3, NULL); decode("\016", 1, NULL);
    decode("\xff", 1, NULL);
    for (unsigned i = 0; i <= 256; i++) assert(query(i) == 0);
    puts("decoder fixtures and 257 query buffer sizes passed");
}
'''
with tempfile.TemporaryDirectory(prefix="hp-bioscfg-fixtures-") as tmp:
    cfile = Path(tmp) / "fixtures.c"
    cfile.write_text(shim + decoder + fixtures + setup + checks)
    executable = Path(tmp) / "fixtures"
    subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-Wall", "-Wextra",
                    "-Werror", str(cfile), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
