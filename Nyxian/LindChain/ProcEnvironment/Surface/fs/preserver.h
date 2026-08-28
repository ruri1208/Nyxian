#ifndef KSURFACE_FS_PRESERVER_H
#define KSURFACE_FS_PRESERVER_H

#include <mach/kern_return.h>
#include <stdint.h>
#include <limits.h>
#include <stddef.h>

typedef enum: uint8_t {
    kFSNodeTypeSymbolicLink,
    kFSNodeTypeDirectory,
} FSNodeType;

typedef struct {
    FSNodeType type;
    char name[PATH_MAX];
    char target[PATH_MAX];
} FSPreserverNode;

kern_return_t ksurface_fs_preserver_add_node(FSPreserverNode node);

typedef struct {
    FSNodeType type;
    const char *name;
    const char *target;
} FSPreserverDesc;

kern_return_t ksurface_fs_preserver_add_nodes(const FSPreserverDesc *v, size_t count, size_t *failed_index);
kern_return_t ksurface_fs_preserver_kickstart(void);

#endif /* KSURFACE_FS_PRESERVER_H */
