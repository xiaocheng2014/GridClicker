#!/bin/bash
set -e

APP_NAME="gridclicker"
VERSION="1.0.0"
BUILD_DIR="build_deb"

echo "Creating build structure..."
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/DEBIAN
mkdir -p $BUILD_DIR/opt/$APP_NAME
mkdir -p $BUILD_DIR/usr/lib/systemd/user

# 1. Create Control file
cat << EOF > $BUILD_DIR/DEBIAN/control
Package: $APP_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Maintainer: Gemini Agent
Description: A full keyboard mouse control tool using grid navigation.
EOF

# 2. Copy files
cp main.py $BUILD_DIR/opt/$APP_NAME/
cp requirements.txt $BUILD_DIR/opt/$APP_NAME/
cp gridclicker.service $BUILD_DIR/usr/lib/systemd/user/

# 3. Create post-inst script for venv setup
cat << 'EOF' > $BUILD_DIR/DEBIAN/postinst
#!/bin/bash
set -e
echo "Setting up virtual environment..."
python3 -m venv /opt/gridclicker/venv
/opt/gridclicker/venv/bin/pip install -r /opt/gridclicker/requirements.txt
echo "Installation complete. Enable with: systemctl --user enable --now gridclicker"
EOF
chmod 755 $BUILD_DIR/DEBIAN/postinst

# 4. Build DEB
dpkg-deb --build $BUILD_DIR ${APP_NAME}_${VERSION}_all.deb
echo "Build complete: ${APP_NAME}_${VERSION}_all.deb"
