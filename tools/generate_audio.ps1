param(
    [switch]$Force
)

# Original, deterministic mono PCM effects for the prototype.
# Run from any directory: pwsh -File tools/generate_audio.ps1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sampleRate = 22050
$twoPi = 2.0 * [Math]::PI
$random = [System.Random]::new(230923)
$outputDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets/audio'
$effects = @(
    @{ Name = 'hit'; Duration = 0.20; Peak = 0.62 }
    @{ Name = 'absorb'; Duration = 0.48; Peak = 0.50 }
    @{ Name = 'cast'; Duration = 0.25; Peak = 0.43 }
    @{ Name = 'whip'; Duration = 0.22; Peak = 0.48; Seed = 230924 }
    @{ Name = 'player_spit'; Duration = 0.27; Peak = 0.43; Seed = 230925 }
    @{ Name = 'enemy_charge'; Duration = 0.64; Peak = 0.42; Seed = 230926 }
    @{ Name = 'enemy_spit'; Duration = 0.30; Peak = 0.46; Seed = 230927 }
    @{ Name = 'impact_whip'; Duration = 0.16; Peak = 0.58; Seed = 2610141 }
    @{ Name = 'impact_acid'; Duration = 0.48; Peak = 0.48; Seed = 2610142 }
    @{ Name = 'impact_web'; Duration = 0.32; Peak = 0.48; Seed = 2610143 }
    @{ Name = 'impact_spikes'; Duration = 0.30; Peak = 0.58; Seed = 2610144 }
    @{ Name = 'acid_gather'; Duration = 0.18; Peak = 0.30; Seed = 2610151 }
    @{ Name = 'acid_release'; Duration = 0.20; Peak = 0.42; Seed = 2610152 }
    @{ Name = 'web_gather'; Duration = 0.18; Peak = 0.28; Seed = 2610153 }
    @{ Name = 'web_release'; Duration = 0.19; Peak = 0.40; Seed = 2610154 }
    @{ Name = 'spikes_gather'; Duration = 0.35; Peak = 0.30; Seed = 2610155 }
    @{ Name = 'spikes_release'; Duration = 0.26; Peak = 0.43; Seed = 2610156 }
    @{ Name = 'shell_gather'; Duration = 0.10; Peak = 0.28; Seed = 2610157 }
    @{ Name = 'shell_open'; Duration = 0.25; Peak = 0.38; Seed = 2610158 }
    @{ Name = 'shell_block'; Duration = 0.22; Peak = 0.48; Seed = 2610159 }
)

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

foreach ($effect in $effects) {
    $path = Join-Path $outputDirectory ($effect.Name + '.wav')
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        "Unchanged: $path"
        continue
    }
    $effectRandom = $random
    if ($effect.ContainsKey('Seed')) {
        $effectRandom = [System.Random]::new([int]$effect.Seed)
    }
    $sampleCount = [int][Math]::Round($effect.Duration * $sampleRate)
    $samples = [double[]]::new($sampleCount)
    $filteredNoise = 0.0
    $peak = 0.0

    for ($i = 0; $i -lt $sampleCount; $i++) {
        $t = $i / [double]$sampleRate
        $noise = 2.0 * $effectRandom.NextDouble() - 1.0
        $filteredNoise = 0.71 * $filteredNoise + 0.29 * $noise

        switch ($effect.Name) {
            'acid_gather' {
                $rise = [Math]::Sin($twoPi * (150.0 * $t + 1200.0 * $t * $t) + 0.55 * [Math]::Sin($twoPi * 28 * $t))
                $value = ($rise * 0.72 + $filteredNoise * 0.28) * [Math]::Pow($t / $effect.Duration, 0.6)
            }
            'acid_release' {
                $value = (0.55 * ($noise - $filteredNoise) + 0.45 * [Math]::Sin($twoPi * (420 * $t - 650 * $t * $t))) * [Math]::Exp(-19 * $t)
            }
            'web_gather' {
                $value = (0.84 * [Math]::Sin($twoPi * (105 * $t + 650 * $t * $t)) + 0.16 * $filteredNoise) * [Math]::Pow($t / $effect.Duration, 0.7)
            }
            'web_release' {
                $value = (0.78 * [Math]::Sin($twoPi * (280 * $t - 420 * $t * $t)) + 0.22 * $filteredNoise) * [Math]::Exp(-20 * $t)
            }
            'spikes_gather' {
                $value = (0.65 * $filteredNoise + 0.35 * [Math]::Sin($twoPi * (85 * $t + 110 * $t * $t))) * [Math]::Pow($t / $effect.Duration, 0.9)
            }
            'spikes_release' {
                $value = (0.54 * [Math]::Sin($twoPi * (110 * $t - 95 * $t * $t)) + 0.46 * $filteredNoise) * [Math]::Exp(-15 * $t)
            }
            'shell_gather' {
                $value = [Math]::Sin($twoPi * (300 * $t + 1600 * $t * $t)) * ($t / $effect.Duration)
            }
            'shell_open' {
                $value = (0.56 * [Math]::Sin($twoPi * 440 * $t) + 0.28 * [Math]::Sin($twoPi * 660 * $t) + 0.16 * $filteredNoise) * [Math]::Exp(-13 * $t)
            }
            'shell_block' {
                $value = (0.55 * [Math]::Sin($twoPi * 330 * $t) + 0.25 * [Math]::Sin($twoPi * 780 * $t) + 0.20 * $filteredNoise) * [Math]::Exp(-19 * $t)
            }
            'impact_whip' {
                # Fast broadband crack with a short, low body; not the swing.
                $crack = $noise * [Math]::Exp(-80.0 * $t)
                $body = [Math]::Sin($twoPi * (175.0 * $t - 340.0 * $t * $t)) * [Math]::Exp(-28.0 * $t)
                $value = 0.68 * $crack + 0.32 * $body
            }
            'impact_acid' {
                # Wet onset followed by airy fizz and falling bubble tones.
                $hiss = ($noise - $filteredNoise) * [Math]::Exp(-6.5 * $t) * (0.65 + 0.35 * [Math]::Sin($twoPi * 31.0 * $t))
                $bubble = [Math]::Sin($twoPi * (410.0 * $t - 250.0 * $t * $t) + 0.8 * [Math]::Sin($twoPi * 23.0 * $t)) * [Math]::Exp(-17.0 * $t)
                $value = 0.60 * $hiss + 0.40 * $bubble
            }
            'impact_web' {
                # Soft adhesive plop, with a low elastic tail and little noise.
                $plop = [Math]::Sin($twoPi * (255.0 * $t - 280.0 * $t * $t) + 0.5 * [Math]::Sin($twoPi * 14.0 * $t))
                $stretch = [Math]::Sin($twoPi * (115.0 * $t + 45.0 * $t * $t))
                $value = (0.65 * $plop + 0.24 * $stretch + 0.11 * $filteredNoise) * [Math]::Exp(-12.0 * $t)
            }
            'impact_spikes' {
                # Heavy earth impact with two brief granular crack layers.
                $thud = [Math]::Sin($twoPi * (94.0 * $t - 70.0 * $t * $t)) * [Math]::Exp(-16.0 * $t)
                $grit = $filteredNoise * ([Math]::Exp(-23.0 * $t) + 0.28 * [Math]::Exp(-[Math]::Pow(($t - 0.045) * 70.0, 2)))
                $value = 0.57 * $thud + 0.43 * $grit
            }
            'hit' {
                $body = [Math]::Sin($twoPi * (125.0 * $t - 135.0 * $t * $t))
                $splash = [Math]::Sin($twoPi * (330.0 * $t - 480.0 * $t * $t))
                $value = (0.56 * $body + 0.26 * $filteredNoise + 0.18 * $splash) * [Math]::Exp(-19.0 * $t)
            }
            'absorb' {
                $rise = $twoPi * (155.0 * $t + 225.0 * $t * $t)
                $bubble = [Math]::Sin($rise + 0.40 * [Math]::Sin($twoPi * 9.0 * $t))
                $shimmer = [Math]::Sin($twoPi * (310.0 * $t + 310.0 * $t * $t))
                $pulse = 0.83 + 0.17 * [Math]::Sin($twoPi * 13.0 * $t)
                $value = (0.62 * $bubble + 0.23 * $shimmer + 0.15 * $filteredNoise) * $pulse * [Math]::Exp(-2.2 * $t)
            }
            'cast' {
                $sweep = $twoPi * (620.0 * $t - 710.0 * $t * $t)
                $value = (0.52 * [Math]::Sin($sweep) + 0.20 * [Math]::Sin(2.0 * $sweep) + 0.28 * $filteredNoise) * [Math]::Exp(-10.0 * $t)
            }
            'whip' {
                $sweep = $twoPi * (180.0 * $t + 950.0 * $t * $t)
                $snap = [Math]::Sin($twoPi * (830.0 * $t - 1100.0 * $t * $t))
                $value = (0.50 * $filteredNoise + 0.32 * [Math]::Sin($sweep) + 0.18 * $snap) * [Math]::Exp(-11.0 * $t)
            }
            'player_spit' {
                $bubble = $twoPi * (370.0 * $t - 420.0 * $t * $t)
                $gurgle = [Math]::Sin($bubble + 0.78 * [Math]::Sin($twoPi * 18.0 * $t))
                $value = (0.64 * $gurgle + 0.22 * [Math]::Sin(0.48 * $bubble) + 0.14 * $filteredNoise) * [Math]::Exp(-8.0 * $t)
            }
            'enemy_charge' {
                $rise = $twoPi * (98.0 * $t + 170.0 * $t * $t)
                $pulse = 0.67 + 0.33 * [Math]::Sin($twoPi * 11.0 * $t)
                $envelope = [Math]::Min(1.0, $t / 0.18)
                $value = (0.72 * [Math]::Sin($rise) + 0.18 * [Math]::Sin(2.0 * $rise) + 0.10 * $filteredNoise) * $pulse * $envelope
            }
            'enemy_spit' {
                $rasp = $twoPi * (240.0 * $t - 250.0 * $t * $t)
                $value = (0.43 * [Math]::Sin($rasp) + 0.36 * $filteredNoise + 0.21 * [Math]::Sin(0.5 * $rasp)) * [Math]::Exp(-8.5 * $t)
            }
        }

        # Both edges end at zero, so repeated playback does not click.
        $attack = [Math]::Min(1.0, $t / 0.003)
        $release = [Math]::Min(1.0, ($sampleCount - 1 - $i) / ($sampleRate * 0.018))
        $samples[$i] = $value * $attack * $release
        $peak = [Math]::Max($peak, [Math]::Abs($samples[$i]))
    }

    if ($peak -le 0.0) { throw "Silent effect: $($effect.Name)" }
    $gain = $effect.Peak / $peak
    $path = Join-Path $outputDirectory ($effect.Name + '.wav')
    $stream = [System.IO.File]::Create($path)
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $dataBytes = $sampleCount * 2
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
        $writer.Write([uint32](36 + $dataBytes))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
        $writer.Write([uint32]16)
        $writer.Write([uint16]1) # PCM
        $writer.Write([uint16]1) # mono
        $writer.Write([uint32]$sampleRate)
        $writer.Write([uint32]($sampleRate * 2))
        $writer.Write([uint16]2)
        $writer.Write([uint16]16)
        $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
        $writer.Write([uint32]$dataBytes)
        foreach ($sample in $samples) {
            $writer.Write([int16][Math]::Round($sample * $gain * 32767.0))
        }
    }
    finally {
        $writer.Dispose()
    }

    '{0}: {1:N3} s, mono PCM16, {2} Hz' -f $path, ($sampleCount / $sampleRate), $sampleRate
}
