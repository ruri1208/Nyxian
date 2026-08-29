#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <LindChain/ProcEnvironment/Utils/klog.h>

void kextension_start(void *mapping)
{
	klog_log("kext", "hello, from kext");
}

void kextension_exit(void)
{
	return;
}

bool kextension_is_unloadable(void)
{
	return true;
}