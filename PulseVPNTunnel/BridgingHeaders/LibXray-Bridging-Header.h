#ifndef LibXray_Bridging_Header_h
#define LibXray_Bridging_Header_h

#include <stddef.h>

typedef long long GoInt;

// LibXray C API — all functions prefixed with CGo
// Accept char* (base64-encoded JSON), return char* (base64-encoded CallResponse JSON)
// Caller must free() returned pointers.

// Xray lifecycle
extern char* CGoRunXray(char* base64Text);
extern char* CGoRunXrayFromJSON(char* base64Text);
extern char* CGoStopXray(void);
extern char* CGoXrayVersion(void);

// Config conversion
extern char* CGoConvertShareLinksToXrayJson(char* base64Text);
extern char* CGOConvertXrayJsonToShareLinks(char* base64Text);

// Utilities
extern char* CGoGetFreePorts(GoInt count);
extern char* CGoPing(char* base64Text);
extern char* CGoQueryStats(char* base64Text);
extern char* CGoTestXray(char* base64Text);

// Geo data
extern char* CGoCountGeoData(char* base64Text);
extern char* CGoReadGeoFiles(char* base64Text);
extern char* CGoBuildMphCache(char* base64Text);

// DNS
extern char* CGoInitDns(char* base64Text);
extern char* CGoResetDns(void);

#endif
