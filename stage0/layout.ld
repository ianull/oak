/*
 * Copyright 2022 The Project Oak Authors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
*/

HIDDEN(TOP = 4096M);
/* We assume BIOS_SIZE will be provided externally. */

MEMORY {
    ram_low : ORIGIN = 0, LENGTH = 1M

    bios : ORIGIN = TOP - BIOS_SIZE, LENGTH = BIOS_SIZE
}

ENTRY(reset_vector)

/* Segment descriptor flags.
 * See Sections 4.7 and 4.8 in AMD64 Architecture Programmer's Manual, Volume 2 for more details.
 */
HIDDEN(SEGMENT_4K = 1 << (32 + 23)); /* G */
HIDDEN(SEGMENT_DEFAULT_32BIT_OP = 1 << (32 + 22)); /* D/B */
HIDDEN(SEGMENT_LONG = 1 << (32 + 21));
HIDDEN(SEGMENT_PRESENT = 1 << (32 + 15)); /* P */
HIDDEN(SEGMENT_USER = 1 << (32 + 12)); /* S */
HIDDEN(SEGMENT_CODE = 1 << (32 + 11));
HIDDEN(SEGMENT_WRITABLE = 1 << (32 + 9));
HIDDEN(SEGMENT_CONFORMING = 1 << (32 + 10));

/* Page table flags */
HIDDEN(PAGE_PRESENT = 1 << 0);
HIDDEN(PAGE_WRITABLE = 1 << 1);
HIDDEN(PAGE_SIZE = 1 << 7);

/* Gate descriptor flags */
HIDDEN(DESCRIPTOR_PRESENT = 1 << 47);
HIDDEN(DESCRIPTOR_INTERRUPT_GATE = 0xE << 40);

/* SEV metadata section types; values defined in
 * https://github.com/tianocore/edk2/blob/master/OvmfPkg/ResetVector/X64/OvmfSevMetadata.asm
 */
HIDDEN(SEV_SECTION_UNMEASURED = 0x1);
HIDDEN(SEV_SECTION_SECRET = 0x2);
HIDDEN(SEV_SECTION_CPUID = 0x3);

SECTIONS {
    /* Lowest 1MB of memory (the real mode address space) where we place a lot of our data structures, as
     * that region is usually avoided by OS kernels.
     * The exact addresses for the various data structures are arbitrary, but wherever possible, we've
     * chosen to follow the examples of either crosvm and/or EDK2.
     * For more background, see:
     * https://wiki.osdev.org/Memory_Map_(x86)
     * https://google.github.io/crosvm/appendix/memory_layout.html
     * https://github.com/tianocore/edk2/blob/master/OvmfPkg/OvmfPkgX64.fdf
     * 
     * These sections have to be marked NOLOAD, otherwise you risk ending up with a 4GB BIOS image.
     */
    .boot.gdt 0x1500 (NOLOAD) : {
        *(.boot.gdt)
    } > ram_low

    /* The GDT provided by crosvm has 4 entries, which means that the (empty) IDT can go
     * immediately after that to address 0x1520. The Rust x86_64::GlobalDescriptorTable has 8
     * entries instead of 4, and the x86_64::InterruptDescriptorTable takes a full 4K of memory, so
     * let's move it to the next page.
     */
    .boot.idt 0x2000 (NOLOAD) : {
        *(.boot.idt)
    } > ram_low
    
    .boot.zero_page 0x7000 (NOLOAD) : {
        *(.boot.zero_page)
    } > ram_low
    ASSERT(SIZEOF(.boot.zero_page) == 4K, "Zero page has to be exactly one page in size")

    boot_stack_pointer = 0x8000;

    .boot.pml4 0x9000 (NOLOAD) : {
        *(.boot.pml4)
    } > ram_low

    .boot.pdpt 0xA000 (NOLOAD) : {
        *(.boot.pdpt)
    } > ram_low

    .boot.pd 0xB000 (NOLOAD) : {
        *(.boot.pd)
    } > ram_low

    .boot.secrets 0xD000 (NOLOAD) : {
        KEEP(*(.boot.secrets))
    } > ram_low
    ASSERT(SIZEOF(.boot.secrets) == 4K, "Secrets section has to be exactly one page in size")

    .boot.cpuid 0xE000 (NOLOAD) : {
        KEEP(*(.boot.cpuid))
    } > ram_low
    ASSERT(SIZEOF(.boot.cpuid) == 4K, "CPUID section has to be exactly one page in size")

    .boot.ghcb ALIGN(4K) (NOLOAD) : {
        KEEP(*(.boot.ghcb))
    } > ram_low
    ASSERT(SIZEOF(.boot.ghcb) == 4K, "GHCB has to be exactly one page in size")

    .boot ALIGN(4K) (NOLOAD) : {
        KEEP(*(.boot))
        . = ALIGN(4K);
    } > ram_low

    ASSERT(. < 640K, "Boot data structures overflow low memory")

    . = ORIGIN(bios);

    .rodata.pml4 ALIGN(4K) : {
        QUAD(ADDR(.rodata.pdpt) | PAGE_PRESENT | PAGE_WRITABLE) /* 0..512 GiB */
    } > bios

    pml4_addr = ADDR(.rodata.pml4);

    .rodata.pdpt ALIGN(4K) : {
        QUAD(ADDR(.rodata.pd) | PAGE_PRESENT | PAGE_WRITABLE) /* 0..1 GiB */
        QUAD(0)
        QUAD(0)
        QUAD(ADDR(.rodata.pd) | PAGE_PRESENT | PAGE_WRITABLE) /* 3..4 GiB */
    } > bios

    pdpt_addr = ADDR(.rodata.pdpt);

    .rodata.pd ALIGN(4K) : {
        QUAD(ADDR(.rodata.pt) | PAGE_PRESENT | PAGE_WRITABLE) /* 0 .. 2 MiB */
        FILL(0x00)
        . += 510 * 8;
        QUAD((TOP - 2M) | PAGE_PRESENT | PAGE_WRITABLE | PAGE_SIZE) /* (4GiB - 2MiB) .. 4 GiB */
    } > bios

    pd_addr = ADDR(.rodata.pd);

    .rodata.pt ALIGN(4K) : {
        /* This will be filled in the bootstrap assembly code. We do this as having 512 lines
         * here would be unwieldy.
         */
        FILL(0x00)
        . += 4K;
    } > bios

    pt_addr = ADDR(.rodata.pt);

    .rodata : {
        KEEP(*(.rodata .rodata.*))
    } > bios

    .text : {
        *(.text .text.*)
    } > bios

    .data : {
        *(.data .data.*)
    } > bios

    .bss (NOLOAD) : {
        bss_start = .;
        *(.bss .bss.*)
        bss_size = . - bss_start;
    } > bios

    .stack ALIGN(4K) (NOLOAD) : {
        . += 32K;
        stack_start = .;
    } > bios

    /* Everything below this line interacts with 16-bit code, so should be kept as close to the end of the file as
     * possible; max TOP - 32k. */

    .text16 TOP - 1K : {
        *(.text16 .text16.*)
    } > bios

    .rodata.gdt ALIGN(8) : {
         /* Null segment */
        QUAD(0)
        /* 64-bit code segment (see Section 4.8.1):
         *  - D=0, as it's ignored when L=1
         *  - L=1 (long mode)
         *  - P=1 (present)
         *  - DPL=00 (ring 0)
         *  - S=1 (user)
         *  - C/D=1 (code)
         *  - C=0
         */
        cs = . - ADDR(.rodata.gdt);
        QUAD(SEGMENT_LONG | SEGMENT_PRESENT | SEGMENT_USER | SEGMENT_CODE)
        /* 64-bit data segment (see Section 4.8.2):
         *  - P=1 (present)
         *  - S=1 (user)
         *  - C/D=0 (data)
         * ...and for 32-bit compatibility (see Section 4.7.3):
         *  - G=1 (limit field is in 4K blocks)
         *  - D/S=1 (default operations are 32-bit)
         *  - limit = 0xFFFFF (in 4K blocks because G=1)
         *
         * Although according to the manual in 64-bit mode WRITABLE should be ignored, at least qemu
         * will cause a #GP if we try to load SS with a segment descriptor that doesn't have it set.
         */
        ds = . - ADDR(.rodata.gdt);
        QUAD(SEGMENT_4K |
             SEGMENT_DEFAULT_32BIT_OP |
             SEGMENT_PRESENT |
             SEGMENT_USER |
             SEGMENT_WRITABLE |
             (0xF << (32 + 16)) | /* Segment Limit [19:16] */
             0xFFFF)              /* Segment Limit [15:0] */
        /* 32-bit code segment, although we only need it for a really short time (see Section 4.7.2):
         *  - G=1 (limit field is in 4K blocks)
         *  - D=1 (default operations are 32-bit)
         *  - P=1 (present)
         *  - S=1 (user)
         *  - C/D=1 (code segment)
         *  - limit = 0xFFFFF (in 4K blocks because G=1)
         */
        cs32 = . - ADDR(.rodata.gdt);
        QUAD(SEGMENT_4K |
             SEGMENT_DEFAULT_32BIT_OP |
             SEGMENT_PRESENT |
             SEGMENT_USER |
             SEGMENT_CODE |
             (0xF << (32 + 16)) | /* Segment Limit [19:16] */
             0xFFFF)              /* Segment Limit [15:0] */
    } > bios

    /* 32-bit interrupt table */
    /* See Section 8.2 in AMD64 Architecture Programmer's Manual, Volume 2 for more details. */
    .rodata.idt ALIGN(8) : {
        QUAD(0) /*  0 - #DE */
        QUAD(0) /*  1 - #DB */
        QUAD(0) /*  2 - #NMI */
        QUAD(0) /*  3 - #BP */
        QUAD(0) /*  4 - #OF */
        QUAD(0) /*  5 - #BR */
        QUAD(0) /*  6 - #UD */
        QUAD(0) /*  7 - #NM */
        QUAD(0) /*  8 - #DF */
        QUAD(0) /*  9 - reserved */
        QUAD(0) /* 10 - #TS */
        QUAD(0) /* 11 - #NP */
        QUAD(0) /* 12 - #SS */
        QUAD(   /* 13 - #GP */
            (gp_handler & 0xFFFF0000) << 32 | /* target offset [31:16] */
            DESCRIPTOR_PRESENT |
            DESCRIPTOR_INTERRUPT_GATE |
            cs32 << 16 |                      /* code segment selector */
            gp_handler & 0xFFFF)              /* target offset [15:0] */
        QUAD(0) /* 14 - #PF */
        QUAD(0) /* 15 - reserved */
        QUAD(0) /* 16 - #MF */
        QUAD(0) /* 17 - #AC */
        QUAD(0) /* 18 - #MC */
        QUAD(0) /* 19 - #XF */
        QUAD(0) /* 20 - reserved */
        QUAD(0) /* 21 - #CP */
        QUAD(0) /* 22 - reserved */
        QUAD(0) /* 23 - reserved */
        QUAD(0) /* 24 - reserved */
        QUAD(0) /* 25 - reserved */
        QUAD(0) /* 26 - reserved */
        QUAD(0) /* 27 - reserved */
        QUAD(0) /* 28 - #HV */
        QUAD(0) /* 29 - #VC */
        QUAD(0) /* 30 - #SX */
        QUAD(0) /* 31 - reserved */
    } > bios
    
    .rodata.gdt_desc ALIGN(8) : {
        SHORT(SIZEOF(.rodata.gdt) - 1)
        LONG(ADDR(.rodata.gdt))
    } > bios

    .rodata.idt_desc ALIGN(8) : {
        SHORT(SIZEOF(.rodata.idt) - 1)
        LONG(ADDR(.rodata.idt))
    } > bios

    gdt_desc_offset = ADDR(.rodata.gdt_desc) & 0xFFFF;
    idt_desc_offset = ADDR(.rodata.idt_desc) & 0xFFFF;

    /* GUIDed tables have to *end* at 0x20 from the end of the file.
     * Documentation about the GUID table format can be found in QEMU docs:
     * https://github.com/qemu/qemu/blob/master/docs/specs/sev-guest-firmware.rst
     * and EDK2 source code:
     * https://github.com/tianocore/edk2/blob/master/OvmfPkg/ResetVector/Ia16/ResetVectorVtf0.asm
     *
     * Unfortunately it doesn't look like `SIZEOF()` works here, so we have to keep track of the data
     * structure size by hand to ensure that it ends at the correct location in memory.
     */
    .guid_tables TOP - 0x20 - (16 + 3*12 + 2*22 + 18) : {
        /* SEV metadata. This data structure is not part of the GUIDed tables, but it makes sense to have
         * them together at the end of the file, thus we put them in the .guid_tables section along with
         * the GUIDed tables themselves. The data structure is defined in the EDK2 source:
         * https://github.com/tianocore/edk2/blob/master/OvmfPkg/ResetVector/X64/OvmfSevMetadata.asm
         *
         * Size: header is 16 bytes + a number of 12-byte sections.
         */
        HIDDEN(sev_guided_structure_start = .);
        /* Header: uint32 signature ("ASEV"), uint32 length, uint32 version, uint32 number of sections */
        BYTE(0x41) BYTE(0x53) BYTE(0x45) BYTE(0x56)
        LONG(sev_guided_structure_end - sev_guided_structure_start)
        LONG(1)
        LONG((sev_guided_structure_end - sev_guided_structure_start - 16) / 12)
        /* Each section has the basic structure of uint32 address, uint32 length, uint32 type
         * The locations of these pages have been chosen to be the same as EDK2:
         * https://github.com/tianocore/edk2/blob/c05a218a9758225ddf94eedb365633f2154551da/OvmfPkg/OvmfPkgX64.fdf
         * Thankfully none of these clashed with existing data structures that we're setting up.
         */
        /* Unmeasured page location */
        LONG(ADDR(.boot.ghcb))
        LONG(SIZEOF(.boot.ghcb))
        LONG(SEV_SECTION_UNMEASURED)
        /* Secrets page location */
        LONG(ADDR(.boot.secrets))
        LONG(SIZEOF(.boot.secrets))
        LONG(SEV_SECTION_SECRET)
        /* CPUID page location */
        LONG(ADDR(.boot.cpuid))
        LONG(SIZEOF(.boot.cpuid))
        LONG(SEV_SECTION_CPUID)
        HIDDEN(sev_guided_structure_end = .);

        /*
         * This is where the GUIDed tables actually start.
         * Size: each entry is 22 bytes + a 18-byte footer.
         */
        HIDDEN(tables_start = .);
        /* SEV metadata descriptor: uint32 offset, uint16 size, 16-byte GUID */
        HIDDEN(sev_metadata_offset_start = .);
        LONG(TOP - sev_guided_structure_start)
        SHORT(sev_metadata_offset_end - sev_metadata_offset_start)
        LONG(0xdc886566)
        SHORT(0x984a)
        SHORT(0x4798)
        SHORT(0x5ea7)
        BYTE(0x55) BYTE(0x85) BYTE(0xa7) BYTE(0xbf) BYTE(0x67) BYTE(0xcc)
        HIDDEN(sev_metadata_offset_end = .);

        /* SEV-ES reset block: uint32 addr, uint16 size, 16-byte GUID */
        HIDDEN(sev_es_reset_block_start = .);
        LONG(0xDEADBEEF) /* Placeholder values */
        SHORT(sev_es_reset_block_end - sev_es_reset_block_start)
        LONG(0x00f771de)
        SHORT(0x1a7e)
        SHORT(0x4fcb)
        SHORT(0x0e89)
        BYTE(0x68) BYTE(0xc7) BYTE(0x7e) BYTE(0x2f) BYTE(0xb4) BYTE(0x4e)
        HIDDEN(sev_es_reset_block_end = .);

        /* Footer: uint16 size, 16-byte GUID */
        SHORT(tables_end - tables_start)
        LONG(0x96b582de)
        SHORT(0x1fb2)
        SHORT(0x45f7)
        SHORT(0xeaba)
        BYTE(0xa3) BYTE(0x66) BYTE(0xc5) BYTE(0x5a) BYTE(0x08) BYTE(0x2d)
        HIDDEN(tables_end = .);
    } > bios

    ASSERT((. == TOP - 0x20), "GUID tables are to expected to end at top - 0x20")

    /* The reset vector needs to be placed 0x10 from the end of the file. */
    .reset_vector TOP - 0x10 : {
        *(.reset_vector)
        FILL(0x00)
        . = TOP;
    } > bios

    /DISCARD/ : {
        *(.eh_frame)
        *(.comment*)
    }
}
