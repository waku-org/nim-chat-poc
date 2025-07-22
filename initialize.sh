#!/bin/bash
echo "Running setup task..."

echo "Init Submodules..."
git submodule update --init --recursive

echo "Building Waku..."
( cd vendor/waku && make -j14 librln)