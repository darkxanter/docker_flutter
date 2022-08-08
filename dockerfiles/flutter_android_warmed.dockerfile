# ----------------------------------------------------------------------------------------
#                                        Dockerfile
# ----------------------------------------------------------------------------------------
# image:       xanter/flutter:${FLUTTER_CHANNEL}${FLUTTER_VERSION}-android-warmed
# repository:  https://github.com/plugfox/docker_flutter
# license:     MIT
# requires:
# + xanter/flutter:<version>-android
# authors:
# + Plague Fox <PlugFox@gmail.com>
# + Maria Melnik
# + Dmitri Z <z-dima@live.ru>
# + DoumanAsh <douman@gmx.se>
# ----------------------------------------------------------------------------------------

ARG FLUTTER_CHANNEL=""
ARG FLUTTER_VERSION=""

FROM xanter/flutter:${FLUTTER_CHANNEL}${FLUTTER_VERSION}-android as build

ARG FLUTTER_CHANNEL
ARG FLUTTER_VERSION

WORKDIR /

#RUN mkdir -p /tmp && find / -xdev | sort > /tmp/before.txt

# Init android dependency and utils & prebuild app
RUN set -eux; cd "${FLUTTER_HOME}/bin" \
    && yes "y" | flutter doctor --android-licenses \
    && dart --disable-analytics \
    && flutter config --no-analytics --enable-android \
    && flutter precache --universal --android \
    && sdkmanager --sdk_root=${ANDROID_HOME} --install 'extras;google;instantapps' \
    && cd /home \
    && flutter create --pub -a kotlin --project-name warmup --platforms android -t app warmup \
    && cd warmup \
    && flutter pub get \
    && flutter build apk --release --no-pub --shrink --target-platform android-arm,android-arm64,android-x64 \
    && cd /home && rm -rf warmup .gradle \
    && sdkmanager --sdk_root=${ANDROID_HOME} --install 'platforms;android-33' 'platforms;android-31' 'platforms;android-30' 'platforms;android-29' 'platforms;android-28' \
    && sdkmanager --list_installed > /home/sdkmanager-list-installed.txt

# Сборка демо проекта
#RUN set -eux; cd "/home/" \
#    && flutter create --pub -a kotlin --project-name warmup --platforms android -t app warmup \
#    && cd warmup \
#    && flutter pub get \
#    && flutter pub upgrade --major-versions \
#    && flutter build apk --release --pub --shrink --target-platform android-arm,android-arm64,android-x64 \
#    && cd .. && rm -rf warmup

#RUN cd / && find / -xdev | sort > /tmp/after.txt

# Add lables
LABEL name="xanter/flutter:${FLUTTER_CHANNEL}${FLUTTER_VERSION}-android-warmed" \
    description="Alpine with flutter & dart for android, warmed up" \
    flutter.channel="${FLUTTER_CHANNEL}" \
    flutter.version="${FLUTTER_VERSION}"