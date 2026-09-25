import QtQuick
import Caelestia.Config
import qs.services

NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial,
        FastEffects,
        DefaultEffects,
        SlowEffects
    }

    property int type: Anim.DefaultSpatial

    duration: {
        if (Motion.enabled)
            return macDuration();

        if (type < Anim.StandardSmall || type > Anim.SlowEffects)
            return Tokens.anim.durations.normal;

        if (type === Anim.FastSpatial)
            return Tokens.anim.durations.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return Tokens.anim.durations.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return Tokens.anim.durations.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return Tokens.anim.durations.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return Tokens.anim.durations.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return Tokens.anim.durations.expressiveSlowEffects;

        const types = ["small", "normal", "large", "extraLarge"];
        const idx = type % 4; // 0-7 are the 4 standard types
        return Tokens.anim.durations[types[idx]];
    }
    easing: {
        if (Motion.enabled)
            return macEasing();

        if (type === Anim.FastSpatial)
            return Tokens.anim.expressiveFastSpatial;
        if (type === Anim.DefaultSpatial)
            return Tokens.anim.expressiveDefaultSpatial;
        if (type === Anim.SlowSpatial)
            return Tokens.anim.expressiveSlowSpatial;
        if (type === Anim.FastEffects)
            return Tokens.anim.expressiveFastEffects;
        if (type === Anim.DefaultEffects)
            return Tokens.anim.expressiveDefaultEffects;
        if (type === Anim.SlowEffects)
            return Tokens.anim.expressiveSlowEffects;

        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return Tokens.anim.emphasized;
        return Tokens.anim.standard;
    }

    function macDuration(): int {
        if (type === Anim.FastSpatial)
            return Motion.fastSpatial;
        if (type === Anim.DefaultSpatial)
            return Motion.defaultSpatial;
        if (type === Anim.SlowSpatial)
            return Motion.slowSpatial;
        if (type === Anim.FastEffects)
            return Motion.fastEffects;
        if (type === Anim.DefaultEffects)
            return Motion.defaultEffects;
        if (type === Anim.SlowEffects)
            return Motion.slowEffects;
        if (type < Anim.StandardSmall || type > Anim.SlowEffects)
            return Motion.standardDurations[1];
        return Motion.standardDurations[type % 4];
    }

    function macEasing(): var {
        if (type === Anim.FastSpatial || type === Anim.DefaultSpatial)
            return Motion.spatial;
        if (type === Anim.SlowSpatial)
            return Motion.spatialSoft;
        if (type >= Anim.FastEffects)
            return Motion.effects;
        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return Motion.emphasized;
        return Motion.standard;
    }
}
