// Доступ к SMC (System Management Controller) через IOKit.
//
// Слой написан на C намеренно: Swift не гарантирует порядок полей структуры,
// а AppleSMC требует точного совместимого с C размещения (проверено:
// sizeof = 80, bytes = 48).
#ifndef CSMC_H
#define CSMC_H

#include <stdint.h>

/// Открывает соединение с AppleSMC. 0 — успех.
int csmc_open(void);

/// Закрывает соединение.
void csmc_close(void);

/// Читает ключ. Возвращает 0 при успехе.
/// out — буфер минимум на 32 байта; size — длина значения; type — код типа.
int csmc_read_key(const char *key, unsigned char *out, uint32_t *size, uint32_t *type);

/// Записывает значение ключа (нужны права root). 0 — успех.
int csmc_write_key(const char *key, const unsigned char *data, uint32_t size);

/// Существует ли ключ и доступен ли он для чтения.
int csmc_key_exists(const char *key);

/// Последний код результата SMC (диагностика).
int csmc_last_result(void);

#endif
