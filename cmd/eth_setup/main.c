#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
#include <sys/sysmacros.h>

#define DEV_NODE		"/dev/ethdriver"

struct dev_info {
	uint32_t if_id;
	uint32_t mac_id;
	uint32_t unused[3];
	uint32_t flags;
};

static struct dev_info info[4] = {
	{ 0x00000000, 0x00000004, .flags = 0x00000100 },
	{ 0x00000001, 0x00000001, .flags = 0x00000100 },
	{ 0x00000002, 0x00000002, .flags = 0x00000100 },
	{ 0x00000003, 0x00000003, .flags = 0x00000100 }
};

struct dev_interface {
	uint8_t if_id;
	uint8_t flag;
	char if_name[9];
};

static struct dev_interface iface[4] = {
	{ 0x00, .if_name = "eth0" },
	{ 0x01, .if_name = "eth1" },
	{ 0x02, .if_name = "eth2" },
	{ 0x03, .if_name = "eth3" },
};

#define IOCTL_SET_DEV_INFO	_IOW('S', 0x34, 0x04)
#define IOCTL_SET_DEV_IF	_IOW('S', 0x02, 0x04)

#define ARRAY_SIZE(x)		(sizeof(x) / sizeof(x[0]))

static void eth_set_dev_info(void)
{
	int fd;
	size_t index;
	int ret;

	fd = open(DEV_NODE, O_RDWR);
	if (fd < 0)
		perror("failed to open " DEV_NODE);

	for (index = 0; index < ARRAY_SIZE(info); index++) {
		ret = ioctl(fd, IOCTL_SET_DEV_INFO, &info[index]);
		printf("%s: index[%lu]: ret = %d\n", __func__, index, ret);
	}

	close(fd);
}

static void eth_set_dev_interface(void)
{
	int fd;
	size_t index;
	int ret;

	fd = open(DEV_NODE, O_RDWR);
	if (fd < 0)
		perror("failed to open " DEV_NODE);

	for (index = 0; index < ARRAY_SIZE(iface); index++) {
		ret = ioctl(fd, IOCTL_SET_DEV_IF, &iface[index]);
		printf("%s: index[%lu]: ret = %d\n", __func__, index, ret);
	}

	close(fd);
}

static void eth_mknod(void)
{
	mode_t mode = S_IFCHR | 0666;
	dev_t dev = makedev(83, 0);

	if (mknod(DEV_NODE, mode, dev) < 0) {
		perror("mknod failed");
		return;
	}

	printf("device %s created, (major=%d, minor=%d)\n",
	       DEV_NODE, major(dev), minor(dev));
}

int main(int argc, const char *argv[])
{
	(void)argc;
	(void)argv;

	printf("ethernet setup...\n");
	eth_mknod();
	eth_set_dev_info();
	eth_set_dev_interface();

	return 0;
}

