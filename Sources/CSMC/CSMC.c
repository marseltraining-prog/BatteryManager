#include "include/CSMC.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9
#define SMC_MAX_BYTES 32

// Раскладка структуры AppleSMC (совместима с C на этой платформе):
// key=0, vers=4, pLimitData=12, keyInfo=28, result=40, data32=44, bytes=48,
// sizeof=80. Проверено пробой на реальной машине.
typedef struct { char major, minor, build, reserved[1]; uint16_t release; } csmc_vers_t;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } csmc_plimit_t;
typedef struct { uint32_t dataSize, dataType; char dataAttributes; } csmc_keyinfo_t;
typedef struct {
    uint32_t key;
    csmc_vers_t vers;
    csmc_plimit_t pLimitData;
    csmc_keyinfo_t keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    char bytes[SMC_MAX_BYTES];
} csmc_key_data_t;

static io_connect_t csmc_conn = 0;
static int csmc_result = 0;
static int csmc_open_count = 0;

static uint32_t csmc_key_to_uint(const char *key) {
    uint32_t value = 0;
    for (int i = 0; i < 4 && key[i]; i++) {
        value = (value << 8) | (unsigned char)key[i];
    }
    return value;
}

static kern_return_t csmc_call(csmc_key_data_t *in, csmc_key_data_t *out) {
    size_t size = sizeof(csmc_key_data_t);
    return IOConnectCallStructMethod(csmc_conn, KERNEL_INDEX_SMC, in, sizeof(*in), out, &size);
}

// Соединение одно на процесс, поэтому открытия считаются: закрытие
// одним потребителем не должно обрывать работу остальных.
int csmc_open(void) {
    if (csmc_conn) {
        csmc_open_count++;
        return 0;
    }
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 1;
    kern_return_t kr = IOServiceOpen(service, mach_task_self(), 0, &csmc_conn);
    IOObjectRelease(service);
    if (kr != KERN_SUCCESS) return 2;
    csmc_open_count = 1;
    return 0;
}

void csmc_close(void) {
    if (csmc_open_count > 0) csmc_open_count--;
    if (csmc_open_count == 0 && csmc_conn) {
        IOServiceClose(csmc_conn);
        csmc_conn = 0;
    }
}

int csmc_last_result(void) { return csmc_result; }

static int csmc_key_info(const char *key, uint32_t *size, uint32_t *type) {
    csmc_key_data_t in, out;
    memset(&in, 0, sizeof(in));
    memset(&out, 0, sizeof(out));
    in.key = csmc_key_to_uint(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    if (csmc_call(&in, &out) != KERN_SUCCESS) return 1;
    if (out.result != 0) { csmc_result = out.result; return 2; }
    *size = out.keyInfo.dataSize;
    *type = out.keyInfo.dataType;
    if (*size == 0 || *size > SMC_MAX_BYTES) return 3;
    return 0;
}

int csmc_read_key(const char *key, unsigned char *out, uint32_t *size, uint32_t *type) {
    if (!csmc_conn) return 1;

    uint32_t key_size = 0, key_type = 0;
    if (csmc_key_info(key, &key_size, &key_type) != 0) return 2;

    csmc_key_data_t in, result;
    memset(&in, 0, sizeof(in));
    memset(&result, 0, sizeof(result));
    in.key = csmc_key_to_uint(key);
    in.keyInfo.dataSize = key_size;
    in.data8 = SMC_CMD_READ_BYTES;
    if (csmc_call(&in, &result) != KERN_SUCCESS) return 3;
    if (result.result != 0) { csmc_result = result.result; return 4; }

    memcpy(out, result.bytes, SMC_MAX_BYTES);
    *size = key_size;
    *type = key_type;
    return 0;
}

int csmc_write_key(const char *key, const unsigned char *data, uint32_t size) {
    if (!csmc_conn) return 1;

    uint32_t key_size = 0, key_type = 0;
    if (csmc_key_info(key, &key_size, &key_type) != 0) return 2;
    if (key_size != size) return 3;

    csmc_key_data_t in, result;
    memset(&in, 0, sizeof(in));
    memset(&result, 0, sizeof(result));
    in.key = csmc_key_to_uint(key);
    in.keyInfo.dataSize = size;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, data, size);

    if (csmc_call(&in, &result) != KERN_SUCCESS) return 4;
    if (result.result != 0) { csmc_result = result.result; return 5; }
    return 0;
}

int csmc_key_exists(const char *key) {
    uint32_t size = 0, type = 0;
    return csmc_key_info(key, &size, &type) == 0 ? 1 : 0;
}
