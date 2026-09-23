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
