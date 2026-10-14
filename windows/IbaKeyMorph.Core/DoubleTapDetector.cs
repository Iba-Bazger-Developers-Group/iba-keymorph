namespace IbaKeyMorph.Core;

/// <summary>
/// Recognises two quick taps of the same modifier (e.g. Shift) with no other key in between.
/// </summary>
public sealed class DoubleTapDetector
{
    private readonly long _maxHoldMs;
    private readonly long _maxGapMs;
    private int? _key;
    private bool _isDown;
    private long _downAt;
    private long _lastUpAt;
    private int _taps;

    public DoubleTapDetector(long maxHoldMs = 250, long maxGapMs = 350)
    {
        _maxHoldMs = maxHoldMs;
        _maxGapMs = maxGapMs;
    }

    public void KeyDown(int key, long nowMs)
    {
        if (_isDown && _key == key)
        {
            return; // auto-repeat
        }

        if (_key != key || nowMs - _lastUpAt > _maxGapMs)
        {
            _taps = 0;
        }

        _key = key;
        _isDown = true;
        _downAt = nowMs;
    }

    /// <summary>Returns true when this release completes a double tap.</summary>
    public bool KeyUp(int key, long nowMs)
    {
        if (!_isDown || _key != key)
        {
            Reset();
            return false;
        }

        _isDown = false;
        if (nowMs - _downAt > _maxHoldMs)
        {
            _taps = 0;
            return false;
        }

        _taps++;
        _lastUpAt = nowMs;
        if (_taps < 2)
        {
            return false;
        }

        _taps = 0;
        return true;
    }

    /// <summary>Any other key or mouse button cancels a pending double tap.</summary>
    public void Reset()
    {
        _key = null;
        _isDown = false;
        _taps = 0;
    }
}
