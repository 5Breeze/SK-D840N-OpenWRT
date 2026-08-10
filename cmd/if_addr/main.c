#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <string.h>

#define PARAM_PATH		"/tagparam/"
#define PARAM_FILE		"paramtag"

typedef struct {
	uint8_t index;
	uint8_t unkown_001[5];
	uint8_t value[6];
} addr_t;

typedef struct {
	uint8_t unkown_000[48];
	addr_t addr[8];
	uint8_t unkown_090[160];
} paramtag_t;

static paramtag_t param;
static bool param_ready;

static uint8_t default_addr[6] = {0x00, 0xa0, 0xa1, 0x61, 0x62, 0x00};

static int read_file(const char *filename, void *buffer, size_t size)
{
	FILE *fp;
	size_t bytes_read;
	int ret = -1;

	if (filename == NULL || buffer == NULL || size == 0)
		return ret;

	fp = fopen(filename, "rb");
	if (fp == NULL)
		return ret;

	bytes_read = fread(buffer, 1, size, fp);
	fclose(fp);

	if (bytes_read == size)
		ret = 0;

	return ret;
}

static int write_file(const char *filename, const void *buffer, size_t size)
{
	FILE *fp;
	size_t bytes_written;
	int ret = -1;

	if (filename == NULL || buffer == NULL || size == 0)
		return ret;

	fp = fopen(filename, "wb");
	if (fp == NULL)
		return ret;

	bytes_written = fwrite(buffer, 1, size, fp);
	fclose(fp);

	if (bytes_written == size)
		ret = 0;

	return ret;
}

static inline void addr_b2s(const uint8_t *b, char *s)
{
	snprintf(s, 18, "%02x:%02x:%02x:%02x:%02x:%02x",
	         b[0], b[1], b[2], b[3], b[4], b[5]);
}

static void load_paramtag(void)
{
	int ret;
	int idx;
	char buffer[32];

	ret = read_file(PARAM_PATH PARAM_FILE, &param, sizeof(param));
	if (ret) {
		printf("The paramtag file does not exist\n");
		return;
	}

	for (idx = 0; idx < 8; idx++) {
		addr_b2s(param.addr[idx].value, buffer);
		printf("load [%d]: %s\n", param.addr[idx].index, buffer);
	}

	param_ready = true;
}

static void build_and_save(void)
{
	int idx;
	uint8_t tmp[6];
	char file[64];
	char buf1[32];
	char buf2[32];
	int ret;

	for (idx = 0; idx < 8; idx++) {
		snprintf(file, sizeof(file), PARAM_PATH "%d_mac_addr",
			 param_ready ? (int)param.addr[idx].index : idx);
		memset(buf1, 0, sizeof(buf1));
		read_file(file, &buf1, sizeof(buf1));

		if (param_ready) {
			memcpy(tmp, param.addr[idx].value, 6);
		} else {
			memcpy(tmp, default_addr, 6);
			tmp[5] = idx;
		}
		addr_b2s(tmp, buf2);

		if (!strcmp(buf1, buf2))
			continue;

		ret = write_file(file, buf2, strlen(buf2));
		printf("%s write: %s (ret = %d)\n", file, buf2, ret);
	}
}

int main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;

	printf("Interface address parse...\n");

	load_paramtag();
	build_and_save();

	return 0;
}

