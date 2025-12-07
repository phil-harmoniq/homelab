#!/bin/bash
curl -sf http://localhost:8008/health || exit 1
exit 0
