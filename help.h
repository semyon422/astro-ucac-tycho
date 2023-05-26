// заголовочный файл с объявлениями функций и структур
// используется как в C, так и в Lua,
// поэтому использование препроцессора здесь не допускается

// функция быстрой сортировки, часть стандартной библиотеки C
void qsort(void *base, size_t num, size_t size, int (*compare) (const void *, const void *));

// структуры для звёзд
typedef struct {
	int32_t ra;
	int32_t de;
	int16_t mag;
	uint8_t rest[34];
} ucac_star;

typedef struct {
	double ra;
	double de;
	double bmag;
	double vmag;
} tycho_star;

// функции сравнения звёзд, используемые в qsort
int compare_ucac(const void *a, const void *b);
int compare_tycho(const void *a, const void *b);

// функции сортировки массивов звёзд
void sort_ucac(ucac_star *ucac, size_t count, size_t size);
void sort_tycho(tycho_star *tycho, size_t count, size_t size);
