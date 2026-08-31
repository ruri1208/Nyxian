#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <LindChain/ProcEnvironment/Surface/kxld/image.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>

kern_return_t kinit(void)
{
	klog_log("$(NXBundleIdentifier)", "hello, from kext");
	return KERN_SUCCESS;
}

EXPORT_KSURFACE_MODULE({
	.magic = KSURFACE_KMOD_MAGIC,
	.abi_version = KSURFACE_KMOD_ABI_VERSION,
	.identifier = "$(NXBundleIdentifier)",
	.version = KMOD_VERSION(1, 0, 0),
	.flags = KMOD_FLAG_NONE,
	.dependency_count = 1,
	.init = kinit,
	.deinit = NULL,
	.start = NULL,
	.stop = NULL,
	.dependencies = {
		{
			.identifier = "ksurface",
			.min_version = KMOD_VERSION(0, 11, 4),
			.max_version = KMOD_VERSION(0, 11, 4),
		}
	},
})
