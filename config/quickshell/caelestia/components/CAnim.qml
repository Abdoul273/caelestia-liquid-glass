import QtQuick
import Caelestia.Config
import qs.services

ColorAnimation {
    duration: Motion.enabled ? Motion.slowEffects : Tokens.anim.durations.expressiveSlowEffects
    easing: Motion.enabled ? Motion.effects : Tokens.anim.expressiveSlowEffects
}
