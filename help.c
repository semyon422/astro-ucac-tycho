#include <stddef.h>
#include <stdint.h>
#include "help.h"

// функции сравнения звёзд, используемые в qsort
int compare_ucac(const void *a, const void *b) {
	const ucac_star *p1 = (ucac_star *)a;
	const ucac_star *p2 = (ucac_star *)b;
	if (p1->de < p2->de)
		return -1;
	else if (p1->de > p2->de)
		return +1;
	else
		return 0;
}

int compare_tycho(const void *a, const void *b) {
	const tycho_star *p1 = (tycho_star *)a;
	const tycho_star *p2 = (tycho_star *)b;
	if (p1->de < p2->de)
		return -1;
	else if (p1->de > p2->de)
		return +1;
	else
		return 0;
}

// функции сортировки массивов звёзд
void sort_ucac(ucac_star *ucac, size_t count, size_t size) {
	qsort(ucac, count, size, compare_ucac);
}

void sort_tycho(tycho_star *tycho, size_t count, size_t size) {
	qsort(tycho, count, size, compare_tycho);
}
