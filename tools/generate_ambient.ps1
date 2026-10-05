param(
    [switch]$Force
)

# Original quiet cave ambience. All oscillator and modulation frequencies
# complete whole cycles in ten seconds, making the WAV itself loop cleanly.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sampleRate = 22050
$durationSeconds = 10
$frameCount = $sampleRate * $durationSeconds
$targetPeak = 0.14
$twoPi = 2.0 * [Math]::PI
$path = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets/audio/cavern_ambient_loop.wav'

if ((Test-Path -LiteralPath $path) -and -not $Force) {
    throw "File already exists: $path. Use -Force to regenerate it."
}

$left = [double[]]::new($frameCount)
$right = [double[]]::new($frameCount)
$peak = 0.0

for ($i = 0; $i -lt $frameCount; $i++) {
    $t = $i / [double]$sampleRate

    # A low minor wash with a small airy overtone. No transient or melody.
    $root = [Math]::Cos($twoPi * 110.0 * $t)
    $minorThird = [Math]::Cos($twoPi * 130.8 * $t)
    $fifth = [Math]::Cos($twoPi * 164.8 * $t)
    $octave = [Math]::Cos($twoPi * 220.0 * $t)
    $airA = [Math]::Cos($twoPi * 440.1 * $t)
    $airB = [Math]::Cos($twoPi * 523.2 * $t)
    $leftBreath = 0.74 + 0.09 * [Math]::Cos($twoPi * 0.1 * $t) + 0.06 * [Math]::Cos($twoPi * 0.3 * $t)
    $rightBreath = 0.74 + 0.08 * [Math]::Cos($twoPi * 0.2 * $t) + 0.06 * [Math]::Cos($twoPi * 0.4 * $t)

    $left[$i] = (0.38 * $root - 0.22 * $minorThird + 0.18 * $fifth - 0.11 * $octave + 0.045 * $airA - 0.025 * $airB) * $leftBreath
    $right[$i] = (0.36 * $root - 0.19 * $minorThird + 0.20 * $fifth - 0.12 * $octave - 0.030 * $airA + 0.045 * $airB) * $rightBreath
    $peak = [Math]::Max($peak, [Math]::Max([Math]::Abs($left[$i]), [Math]::Abs($right[$i])))
}

if ($peak -le 0.0) { throw 'Ambient loop is silent.' }
$gain = $targetPeak / $peak
$stream = [System.IO.File]::Create($path)
$writer = [System.IO.BinaryWriter]::new($stream)
try {
    $dataBytes = $frameCount * 4
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('RIFF'))
    $writer.Write([uint32](36 + $dataBytes))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('WAVE'))
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('fmt '))
    $writer.Write([uint32]16)
    $writer.Write([uint16]1) # PCM
    $writer.Write([uint16]2) # stereo
    $writer.Write([uint32]$sampleRate)
    $writer.Write([uint32]($sampleRate * 4))
    $writer.Write([uint16]4)
    $writer.Write([uint16]16)
    $writer.Write([System.Text.Encoding]::ASCII.GetBytes('data'))
    $writer.Write([uint32]$dataBytes)
    for ($i = 0; $i -lt $frameCount; $i++) {
        $writer.Write([int16][Math]::Round($left[$i] * $gain * 32767.0))
        $writer.Write([int16][Math]::Round($right[$i] * $gain * 32767.0))
    }
}
finally {
    $writer.Dispose()
}

'{0}: {1} s, stereo PCM16, {2} Hz, peak {3:N2}' -f $path, $durationSeconds, $sampleRate, $targetPeak
