#ifndef SOCKET_UTILS_H
#define SOCKET_UTILS_H

#include <sys/socket.h>

// Function to send a file descriptor over a Unix socket
int send_fd(int sock, int fd, void* data, int datalen);

#endif // SOCKET_UTILS_H
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int send_fd(int sock, int fd, void* data, int datalen) {
    struct msghdr msg;
    struct iovec io;
    char buf[1]; // Placeholder data
    char ctrl_buf[CMSG_SPACE(sizeof(int))]; // Control message buffer
    struct cmsghdr *cmsg;

    printf("Size of buf: %zu bytes\n", sizeof(buf));

    // Initialize message header
    memset(&msg, 0, sizeof(msg));

    // Prepare I/O vector
    io.iov_base = data;// buf;
    io.iov_len = datalen;// sizeof(buf);

    msg.msg_iov = &io;
    msg.msg_iovlen = 1;

    // Prepare control message for sending the file descriptor
    msg.msg_control = ctrl_buf;
    msg.msg_controllen = sizeof(ctrl_buf);

    cmsg = (struct cmsghdr *)ctrl_buf; // Directly cast to cmsghdr
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    cmsg->cmsg_len = CMSG_LEN(sizeof(int)); // Set length

   *((int *)((char *)cmsg + sizeof(struct cmsghdr))) = fd; // Set file descriptor

   printf("cmsghdr contents:\n");
    printf("cmsg_level: 0x%x\n", cmsg->cmsg_level);      // 0x1
    printf("cmsg_type: 0x%x\n", cmsg->cmsg_type);        // 0x1
    printf("cmsg_len: 0x%x\n", cmsg->cmsg_len);          // 0x14
    printf("msg.msg_controllen: 0x%x\n", msg.msg_controllen); // 0x18
    for (size_t i = 0; i < msg.msg_controllen; i++) {
        printf("0x%02x ", ((unsigned char *)msg.msg_control)[i]);      //0x14 0x00 0x00 0x00
    }

    // 0x14 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x01 0x00 0x00 0x00 0x01 0x00 0x00 0x00 0x04 0x00 0x00 0x00 0x04 0x00 0x00 0x00

    printf("Size of buf: %zu bytes\n", sizeof(buf));


   // Send the message with the file descriptor
   return sendmsg(sock, &msg, 0);
}

