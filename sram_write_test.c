#include <stdio.h>
#include <stdint.h>

#define SRAM_BASE  0x00000000u
#define BANK_SIZE  0x00008000u
#define BANK_NUM   4
#define OFFSET     0x00004000u
#define N_WORDS    32

static volatile uint32_t *bank_ptr(int b)
{
    return (volatile uint32_t *)(SRAM_BASE + (uint32_t)b * BANK_SIZE + OFFSET);
}

int main(void)
{
    for (int b = 0; b < BANK_NUM; b++) {
        volatile uint32_t *p = bank_ptr(b);
        for (int i = 0; i < N_WORDS; i++)
            p[i] = 0xA5A50000u | ((uint32_t)b << 8) | (uint32_t)i;
    }

    for (int b = 0; b < BANK_NUM; b++) {
        volatile uint32_t *p = bank_ptr(b);
        for (int i = 0; i < N_WORDS; i++) {
            if (p[i] != (0xA5A50000u | ((uint32_t)b << 8) | (uint32_t)i)) {
                printf("FAIL bank %d word %d\n", b, i);
                return 1;
            }
        }
    }

    printf("PASS %d banks x %d words, bank0=0x%08x\n", BANK_NUM, N_WORDS,
           (unsigned)bank_ptr(0));
    return 0;
}
