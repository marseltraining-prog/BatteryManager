// Привилегированный helper для управления зарядом через SMC.
// Запускается с setuid root (chmod 4755), принимает только три команды:
//   hold   — остановить зарядку (CHIE=08 или другой найденный ключ)
//   allow  — разрешить зарядку (CHIE=00)
//   status — прочитать и вывести текущее значение ключа
//
// Компиляция: см. scripts/build-helper.sh
// Установка: sudo scripts/install-helper.sh

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../CSMC/CSMC.c"

// Кандидаты управления зарядом (в порядке приоритета).
typedef struct {
    const char *key;
    unsigned char hold_value;
    unsigned char allow_value;
    int size;
    const char *note;
} ControlKey;

static const ControlKey candidates[] = {
    // macOS 26: CHTE (4 байта, "tahoe")
    {"CHTE", 0x01, 0x00, 4, "tahoe charge control"},
    // M1/M2: CH0B + CH0C (legacy)
    {"CH0B", 0x02, 0x00, 1, "legacy charging inhibit"},
    // CHSC намеренно не пишется: на проверенных моделях он только для
    // чтения, а значения «удерживать»/«разрешить» для него не подтверждены.
    // macOS 27: CHIE (управление адаптером = разряд/заряд)
    {"CHIE", 0x08, 0x00, 1, "adapter control (discharge)"},
    {NULL, 0, 0, 0, NULL}
};

static int try_write(const char *key, unsigned char value, int expected_size) {
    unsigned char data[8] = {0};
    if (expected_size == 4) {
        data[0] = value; data[1] = 0; data[2] = 0; data[3] = 0;
    } else {
        data[0] = value;
    }
    return csmc_write_key(key, data, expected_size);
}

static void print_usage(const char *prog) {
    fprintf(stderr, "Использование: %s <hold|allow|status>\n", prog);
    fprintf(stderr, "  hold   — остановить зарядку\n");
    fprintf(stderr, "  allow  — разрешить зарядку\n");
    fprintf(stderr, "  status — показать текущее состояние\n");
    exit(2);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        print_usage(argv[0]);
    }

    const char *cmd = argv[1];
    int is_hold = (strcmp(cmd, "hold") == 0);
    int is_allow = (strcmp(cmd, "allow") == 0);
    int is_status = (strcmp(cmd, "status") == 0);

    if (!is_hold && !is_allow && !is_status) {
        print_usage(argv[0]);
    }

    if (csmc_open() != 0) {
        fprintf(stderr, "Ошибка: не удалось открыть AppleSMC.\n");
        return 1;
    }

    // Для status — показать все кандидаты
    if (is_status) {
        printf("Ключи управления зарядом:\n");
        for (int i = 0; candidates[i].key != NULL; i++) {
            unsigned char buf[32]; // csmc_read_key всегда пишет 32 байта
            uint32_t size = 0, type = 0;
            if (csmc_read_key(candidates[i].key, buf, &size, &type) == 0 && size > 0) {
                printf("  ✓ %s (размер=%d): ", candidates[i].key, size);
                for (uint32_t b = 0; b < size; b++) {
                    printf("%02x ", buf[b]);
                }
                printf("— %s\n", candidates[i].note);
            } else {
                printf("  ✗ %s — отсутствует\n", candidates[i].key);
            }
        }
        csmc_close();
        return 0;
    }

    // hold или allow: пробуем кандидаты по порядку
    for (int i = 0; candidates[i].key != NULL; i++) {
        const ControlKey *ck = &candidates[i];
        
        // Проверяем, существует ли ключ
        unsigned char test[32];
        uint32_t size = 0, type = 0;
        if (csmc_read_key(ck->key, test, &size, &type) != 0 || size == 0) {
            continue; // ключ отсутствует, пробуем следующий
        }

        // Пытаемся записать
        unsigned char value = is_hold ? ck->hold_value : ck->allow_value;
        if (try_write(ck->key, value, ck->size) == 0) {
            printf("%s: %s (ключ %s)\n", 
                   is_hold ? "Зарядка остановлена" : "Зарядка разрешена",
                   ck->note, ck->key);
            
            // Для CH0B пишем также CH0C (companion key)
            if (strcmp(ck->key, "CH0B") == 0) {
                try_write("CH0C", value, 1);
            }
            
            csmc_close();
            return 0;
        }
    }

    // Ни один ключ не сработал
    fprintf(stderr, "Ошибка: управление зарядом не поддерживается на этой модели.\n");
    fprintf(stderr, "Ни один из известных ключей SMC не принял запись.\n");
    csmc_close();
    return 1;
}
