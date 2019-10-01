#!/bin/bash
set -e
docker build '.' --tag 'valonnopea/php:5.4.45-fpm'
docker build '.' --tag 'valonnopea/php:5.4-fpm'
