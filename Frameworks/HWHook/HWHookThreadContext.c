/*
 SPDX-License-Identifier: AGPL-3.0-or-later

 Copyright (C) 2025 - 2026 emexlab

 This file is part of Nyxian.

 Nyxian is free software: you can redistribute it and/or modify
 it under the terms of the GNU Affero General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Nyxian is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 GNU Affero General Public License for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Nyxian. If not, see <https://www.gnu.org/licenses/>.
*/

#include "CFRuntime.h"
#include "HWHookThreadContext.h"
#include <pthread.h>
#include <mach/mach.h>

static CFTypeID gHWHookThreadContextTypeID = _kCFRuntimeNotATypeID;

struct __HWHookThreadContext {
    CFRuntimeBase _base;
    Boolean entered;
    CFMutableArrayRef symbols;
};

static void __HWHookThreadContextInit(CFTypeRef cf)
{
    HWHookThreadContextRef context = (HWHookThreadContextRef)cf;
    context->entered = false;
    context->symbols = NULL;
}

static void __HWHookThreadContextFinalize(CFTypeRef cf)
{
    HWHookThreadContextRef context = (HWHookThreadContextRef)cf;
    if(context->entered)
    {
        HWHookThreadContextExit(context);
    }
    if(context->symbols != NULL)
    {
        CFRelease(context->symbols);
    }
}

static const CFRuntimeClass gHWHookThreadContext = {
    0,                              /* version */
    "HWHookThreadContext",          /* class name */
    __HWHookThreadContextInit,      /* init */
    NULL,                           /* copy */
    __HWHookThreadContextFinalize,  /* finalize */
    NULL,                           /* equal */
    NULL,                           /* hash */
    NULL,                           /* copyFormattingDesc */
    NULL,                           /* copyDebugDesc */
    NULL,
    NULL,
    0
};

CFTypeID HWHookThreadContextGetTypeID(void)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gHWHookThreadContextTypeID = _CFRuntimeRegisterClass(&gHWHookThreadContext);
    });
    return gHWHookThreadContextTypeID;
}

typedef struct {
    thread_t target;
    arm_debug_state64_t state;
    
    bool post_debug_set;
    bool teardown;
    
    mach_port_t exceptionPort;
    
    /* old exception port configurations */
    mach_msg_type_number_t old_count;
    exception_mask_t old_masks[EXC_TYPES_COUNT];
    mach_port_t old_ports[EXC_TYPES_COUNT];
    exception_behavior_t old_behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t old_flavors[EXC_TYPES_COUNT];
    
    HWHookThreadContextRef context;
} hwhook_server_ctx_t;

typedef struct {
    union {
        __Request__exception_raise_t v;
        uint8_t pad[1024];
    };
} __Request__exception_raise_large_t;

_Thread_local HWHookThreadContextRef tCurrentContext = NULL; /* retained */
_Thread_local hwhook_server_ctx_t tCurrentServerContext;
void *__HWHookThreadContextServer(void *ctxp)
{
    hwhook_server_ctx_t *ctx = ctxp;
    
    mach_port_t port = ctx->exceptionPort;
    
    /* will carry request buffer */
    __Request__exception_raise_large_t request;
    
    for(;;)
    {
        /* receiving pseudo exception */
        request.v.Head.msgh_local_port = port;
        request.v.Head.msgh_size = (mach_msg_size_t)sizeof(request);
        mach_msg_return_t mr = mach_msg(&(request.v.Head), MACH_RCV_MSG | MACH_RCV_LARGE, 0, sizeof(request), port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if(mr != MACH_MSG_SUCCESS)
        {
            printf("[!] failed to receive exception\n");
            return NULL;
        }
        printf("[+] received exception\n");
        
        if(!ctx->post_debug_set)
        {
            printf("[*] target thread is still at setup\n");
            
            /* setting debug state */
            kern_return_t kr = thread_set_state(request.v.thread.name, ARM_DEBUG_STATE64, (thread_state_t)&ctx->state, ARM_DEBUG_STATE64_COUNT);
            if(kr != KERN_SUCCESS)
            {
                printf("[!] failed to set debug thread state\n");
                return NULL;
            }
            printf("[+] set debug thread state\n");
            
            /* skip over pseudo exception */
            arm_thread_state64_t state;
            mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
            kr = thread_get_state(request.v.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
            if(kr != KERN_SUCCESS)
            {
                printf("[!] failed to get normal thread state\n");
                return NULL;
            }
            printf("[+] got normal thread state\n");
            
            /* skipping over __builtin_trap */
            state.__pc += 4;
            
            kr = thread_set_state(request.v.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, count);
            if(kr != KERN_SUCCESS)
            {
                printf("[!] failed to set normal thread state\n");
                return NULL;
            }
            printf("[+] set normal thread state\n");
            
            ctx->post_debug_set = true;
        }
        else if(ctx->teardown)
        {
            printf("[*] target thread requested teardown\n");
            
            /* clear hooks */
            arm_debug_state64_t clear;
            memset(&clear, 0, sizeof(clear));
            kern_return_t kr = thread_set_state(request.v.thread.name, ARM_DEBUG_STATE64, (thread_state_t)&clear, ARM_DEBUG_STATE64_COUNT);
            if(kr != KERN_SUCCESS)
            {
                printf("[!] failed to clear debug state\n");
            }
            
            arm_thread_state64_t state;
            mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
            kr = thread_get_state(request.v.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
            if(kr == KERN_SUCCESS)
            {
                state.__pc += 4;
                thread_set_state(request.v.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, count);
            }
            
            if(ctx->old_count > 0)
            {
                for(mach_msg_type_number_t i = 0; i < ctx->old_count; i++)
                {
                    thread_set_exception_ports(request.v.thread.name, ctx->old_masks[i], ctx->old_ports[i], ctx->old_behaviors[i], ctx->old_flavors[i]);
                }
            }
            else
            {
                thread_set_exception_ports(request.v.thread.name, EXC_MASK_BREAKPOINT, MACH_PORT_NULL, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
            }
            
            mach_port_mod_refs(mach_task_self(), ctx->exceptionPort, MACH_PORT_RIGHT_RECEIVE, -1);
            mach_port_deallocate(mach_task_self(), ctx->exceptionPort);
            
            __Reply__exception_raise_t reply;
            memset(&reply, 0, sizeof(reply));
            reply.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(request.v.Head.msgh_bits), 0);
            reply.Head.msgh_id = request.v.Head.msgh_id + 100;
            reply.Head.msgh_local_port = MACH_PORT_NULL;
            reply.Head.msgh_remote_port = request.v.Head.msgh_remote_port;
            reply.Head.msgh_size = sizeof(reply);
            reply.NDR = NDR_record;
            reply.RetCode = KERN_SUCCESS;
            mr = mach_msg(&reply.Head, MACH_SEND_MSG, reply.Head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
            mach_msg_destroy(&(request.v.Head));
            if(mr != KERN_SUCCESS)
            {
                printf("[!] failed to send reply to the kernel\n");
                return NULL;
            }
            printf("[+] reply send to the kernel\n");
            printf("[+] baiii :3\n\n");
            return NULL;
        }
        else
        {
            /* debug register are set */
            printf("[*] target thread called hook\n");
            
            arm_thread_state64_t state;
            mach_msg_type_number_t count = ARM_THREAD_STATE64_COUNT;
            kern_return_t kr = thread_get_state(request.v.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, &count);
            if(kr != KERN_SUCCESS)
            {
                printf("[!] failed to get normal thread state\n");
                return NULL;
            }
            printf("[+] got normal thread state\n");
            
            /* matching hook */
            HWHookRef matchingHook = NULL;
            CFIndex hookCount = CFArrayGetCount(ctx->context->symbols);
            for(CFIndex index = 0; index < hookCount; index++)
            {
                HWHookRef hook = (HWHookRef)CFArrayGetValueAtIndex(ctx->context->symbols, index);
                if(state.__pc == (uint64_t)HWHookGetSymbolPtr(hook))
                {
                    matchingHook = hook;
                    break;
                }
            }
            
            if(matchingHook == NULL)
            {
                printf("[!] failed to match the hook\n");
                return NULL;
            }
            void *symbolPtr = HWHookGetSymbolPtr(matchingHook);
            void *replacementPtr = HWHookGetReplacementPtr(matchingHook);
            printf("[+] matchingHook = %p\n", matchingHook);
            printf("    symbolPtr = %p\n", symbolPtr);
            printf("    replacementPtr = %p\n", replacementPtr);
            
            /* now call the replacement */
            state.__pc = (uint64_t)replacementPtr;
            kr = thread_set_state(request.v.thread.name, ARM_THREAD_STATE64, (thread_state_t)&state, count);
            if(kr != KERN_SUCCESS)
            {
                printf("[!] failed to set normal thread state\n");
                return NULL;
            }
            printf("[+] set normal thread state\n");
        }
        
        __Reply__exception_raise_t reply;
        memset(&reply, 0, sizeof(reply));
        reply.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(request.v.Head.msgh_bits), 0);
        reply.Head.msgh_id = request.v.Head.msgh_id + 100;
        reply.Head.msgh_local_port = MACH_PORT_NULL;
        reply.Head.msgh_remote_port = request.v.Head.msgh_remote_port;
        reply.Head.msgh_size = sizeof(reply);
        reply.NDR = NDR_record;
        reply.RetCode = KERN_SUCCESS;
        mr = mach_msg(&reply.Head, MACH_SEND_MSG, reply.Head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        mach_msg_destroy(&(request.v.Head));
        if(mr != KERN_SUCCESS)
        {
            printf("[!] failed to send reply to the kernel\n");
            return NULL;
        }
        printf("[+] reply sent to the kernel\n\n");
    }
    
    return NULL;
}

HWHookThreadContextRef HWHookThreadContextGetCurrent(void)
{
    return tCurrentContext;
}

HWHookThreadContextRef HWHookThreadContextCreate(CFAllocatorRef allocator)
{
    HWHookThreadContextRef context = (HWHookThreadContextRef)_CFRuntimeCreateInstance(allocator, HWHookThreadContextGetTypeID(), sizeof(struct __HWHookThreadContext) - sizeof(CFRuntimeBase), NULL);
    if(context == NULL)
    {
        return NULL;
    }
    
    context->symbols = CFArrayCreateMutable(allocator, 0, &kCFTypeArrayCallBacks);
    if(context->symbols == NULL)
    {
        CFRelease(context);
        return NULL;
    }
    
    return context;
}

Boolean HWHookThreadContextEnter(HWHookThreadContextRef context)
{
    if(context == NULL || tCurrentContext != NULL)
    {
        return false;
    }
    bzero(&tCurrentServerContext, sizeof(tCurrentServerContext));
    
    /* backing up current exception ports */
    thread_t currentThread = mach_thread_self();
    thread_get_exception_ports(currentThread, EXC_MASK_BREAKPOINT, tCurrentServerContext.old_masks, &tCurrentServerContext.old_count, tCurrentServerContext.old_ports, tCurrentServerContext.old_behaviors, tCurrentServerContext.old_flavors);
    
    /* creating thread port exception port */
    mach_port_options_t opt = { .flags =  MPO_INSERT_SEND_RIGHT };
    mach_port_t exceptionPort = MACH_PORT_NULL;
    kern_return_t kr = mach_port_construct(mach_task_self(), &opt, 0, &exceptionPort);
    if(kr != KERN_SUCCESS)
    {
        goto out_recover_thread_exception_ports;
    }
    tCurrentServerContext.exceptionPort = exceptionPort;
    
    kr = thread_set_exception_ports(currentThread, EXC_MASK_BREAKPOINT, exceptionPort, EXCEPTION_DEFAULT, ARM_THREAD_STATE64);
    if(kr != KERN_SUCCESS)
    {
        goto out_destroy_exception_port;
    }
    
    /* creating detached HWHookThreadContextServer */
    mach_msg_type_number_t old_stateCnt = ARM_DEBUG_STATE64_COUNT;
    kr = thread_get_state(currentThread, ARM_DEBUG_STATE64, (thread_state_t)&tCurrentServerContext.state, &old_stateCnt);
    if(kr != KERN_SUCCESS)
    {
        goto out_stop_server;
    }
    
    CFIndex hookCount = CFArrayGetCount(context->symbols);
    for(CFIndex index = 0; index < hookCount; index++)
    {
        HWHookRef hook = (HWHookRef)CFArrayGetValueAtIndex(context->symbols, index);
        tCurrentServerContext.state.__bvr[index] = (uint64_t)HWHookGetSymbolPtr(hook);
        tCurrentServerContext.state.__bcr[index] = (0xFu << 5) | (0b10u << 1) | 1u;
    }
    tCurrentServerContext.target = currentThread;
    tCurrentContext = context;
    tCurrentServerContext.context = context;
    
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_t thread;
    int rc = pthread_create(&thread, &attr, __HWHookThreadContextServer, &tCurrentServerContext);
    __asm__ volatile ("brk #1" ::: "memory");
    pthread_attr_destroy(&attr);
    if(rc != 0)
    {
        goto out_destroy_exception_port;
    }
    
    return true;
    
out_stop_server:
out_destroy_exception_port:
    mach_port_deallocate(mach_task_self(), exceptionPort);
    mach_port_mod_refs(mach_task_self(), exceptionPort, MACH_PORT_RIGHT_RECEIVE, -1);
out_recover_thread_exception_ports:
    if(tCurrentServerContext.old_count > 0)
    {
        task_set_exception_ports(mach_task_self(), tCurrentServerContext.old_masks[0], tCurrentServerContext.old_ports[0], tCurrentServerContext.old_behaviors[0], tCurrentServerContext.old_flavors[0]);
    }
    else
    {
        task_set_exception_ports(mach_task_self(), EXC_MASK_BREAKPOINT, MACH_PORT_NULL, EXCEPTION_DEFAULT, THREAD_STATE_NONE);
    }
    return false;
}

Boolean HWHookThreadContextExit(HWHookThreadContextRef context)
{
    if(context == NULL || tCurrentContext != context)
    {
        return false;
    }
    
    /* safe cause this thread is not causing a exception in here xD */
    tCurrentServerContext.teardown = true;
    __asm__ volatile ("brk #2" ::: "memory");
    tCurrentContext = NULL;
    
    return true;
}

Boolean HWHookThreadContextAppendHook(HWHookThreadContextRef context,
                                      HWHookRef hook)
{
    if(context == NULL || HWHookThreadContextGetCurrent() == context)
    {
        return false;
    }
    
    CFArrayAppendValue(context->symbols, hook);
    return true;
}
