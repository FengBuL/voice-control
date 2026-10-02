#import <Foundation/Foundation.h>
#include "i2c.h"
#include <assert.h>

static uint32_t capturedReadOffset, capturedReadSize;
IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chip, uint32_t offset, void *buffer, uint32_t size) {
    (void)service; (void)chip;
    capturedReadOffset = offset;
    capturedReadSize = size;
    memset(buffer, 0, size);
    return 0;
}
IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chip, uint32_t address, void *buffer, uint32_t size) {
    (void)service; (void)chip; (void)address; (void)buffer; (void)size;
    return 0;
}

static void checksum(UInt8 *b) {
    b[10] = 0x50;
    for (int i = 0; i < 10; i++) b[10] ^= b[i];
}

int main(void) {
    @autoreleasepool {
        UInt8 b[11] = {0x6e, 0x88, 0x02, 0, VOLUME, 0, 0x01, 0x00, 0, 128, 0};
        checksum(b);
        assert(validDDCReply(b, 11, VOLUME));
        DDCValue value = convertI2CtoDDC((char *)b);
        assert(value.maxValue == 256 && value.curValue == 128);
        assert(!validDDCReply(b, 10, VOLUME));
        assert(!validDDCReply(b, 11, LUMINANCE));
        b[10] ^= 1;
        assert(!validDDCReply(b, 11, VOLUME));
        checksum(b);
        b[3] = 1; checksum(b);
        assert(!validDDCReply(b, 11, VOLUME));
        UInt8 zero[11] = {0};
        assert(!validDDCReply(zero, 11, VOLUME));
        DDCPacket write = createDDCPacket(VOLUME);
        prepareDDCWrite(&write, 128);
        assert(write.data[0] == 0x84 && write.data[1] == 3);
        assert(write.data[3] == 0 && write.data[4] == 128);
        DDCPacket request = createDDCPacket(VOLUME);
        prepareDDCRead(&request);
        assert(request.data[3] == 0xde); // VESA: 6e ^ 51 ^ 82 ^ 01 ^ 62.
        performDDCReadAtChipAddress(NULL, DDC_CHIP_ADDRESS_DEFAULT, &request);
        assert(capturedReadOffset == 0); // Replies are read without a subaddress.
        assert(capturedReadSize == 11); // Full Get VCP Feature Reply, including checksum.
        puts("DDC checks passed: valid, unsupported, corrupt, empty and wrong-feature replies; endian conversion and write packet.");
    }
    return 0;
}
