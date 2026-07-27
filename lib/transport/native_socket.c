/*
 * Native socket connect with detailed error codes.
 */
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <moonbit.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#pragma comment(lib, "ws2_32.lib")

static int wsa_done = 0;
static void ensure_wsa() {
  if (!wsa_done) {
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
    wsa_done = 1;
  }
}

MOONBIT_FFI_EXPORT
int64_t moon_s7_connect(int64_t ip, int64_t port) {
  ensure_wsa();

  unsigned char b0 = (ip >> 24) & 0xFF;
  unsigned char b1 = (ip >> 16) & 0xFF;
  unsigned char b2 = (ip >> 8) & 0xFF;
  unsigned char b3 = ip & 0xFF;
  fprintf(stderr, "[C] Connecting to %d.%d.%d.%d:%lld...\n", b0, b1, b2, b3, (long long)port);

  SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == INVALID_SOCKET) {
    fprintf(stderr, "[C] socket() failed, WSA err=%d\n", WSAGetLastError());
    return -1;
  }
  fprintf(stderr, "[C] socket created, fd=%lld\n", (long long)(intptr_t)s);

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((u_short)port);
  addr.sin_addr.s_addr = htonl((u_long)ip);

  u_long mode = 1;
  ioctlsocket(s, FIONBIO, &mode);

  int ret = connect(s, (struct sockaddr*)&addr, sizeof(addr));
  if (ret == SOCKET_ERROR) {
    int err = WSAGetLastError();
    fprintf(stderr, "[C] connect() returned error, WSA err=%d\n", err);
    if (err == WSAEWOULDBLOCK) {
      fprintf(stderr, "[C] Waiting for connection (10s timeout)...\n");
      fd_set wset;
      FD_ZERO(&wset);
      FD_SET(s, &wset);
      struct timeval tv = { 10, 0 };
      ret = select(0, NULL, &wset, NULL, &tv);
      if (ret <= 0) {
        fprintf(stderr, "[C] select() timeout/error, ret=%d WSA=%d\n", ret, WSAGetLastError());
        closesocket(s);
        return -2;
      }
      fprintf(stderr, "[C] select() OK, checking SO_ERROR...\n");
      int so_err = 0;
      int so_len = sizeof(so_err);
      getsockopt(s, SOL_SOCKET, SO_ERROR, (char*)&so_err, &so_len);
      if (so_err != 0) {
        fprintf(stderr, "[C] SO_ERROR=%d (WSA code)\n", so_err);
        closesocket(s);
        return -3;
      }
    } else {
      fprintf(stderr, "[C] Immediate connect fail, WSA err=%d\n", err);
      closesocket(s);
      return -4;
    }
  } else {
    fprintf(stderr, "[C] connect() succeeded immediately\n");
  }

  mode = 0;
  ioctlsocket(s, FIONBIO, &mode);
  fprintf(stderr, "[C] Connected! fd=%lld\n", (long long)(intptr_t)s);
  return (int64_t)(intptr_t)s;
}

#else
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

MOONBIT_FFI_EXPORT
int64_t moon_s7_connect(int64_t ip, int64_t port) {
  int s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s < 0) { fprintf(stderr, "[C] socket() failed: %s\n", strerror(errno)); return -1; }
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  addr.sin_addr.s_addr = htonl((uint32_t)ip);
  fcntl(s, F_SETFL, O_NONBLOCK);
  int ret = connect(s, (struct sockaddr*)&addr, sizeof(addr));
  if (ret < 0) {
    if (errno == EINPROGRESS) {
      fd_set wset; FD_ZERO(&wset); FD_SET(s, &wset);
      struct timeval tv = { 10, 0 };
      ret = select(s + 1, NULL, &wset, NULL, &tv);
      if (ret <= 0) { close(s); return -2; }
      int err = 0; socklen_t len = sizeof(err);
      getsockopt(s, SOL_SOCKET, SO_ERROR, &err, &len);
      if (err != 0) { close(s); return -3; }
    } else { close(s); return -4; }
  }
  fcntl(s, F_SETFL, fcntl(s, F_GETFL) & ~O_NONBLOCK);
  return (int64_t)s;
}
#endif
