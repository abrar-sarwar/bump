import wordmark from '../assets/wordmark.png'

/**
 * The BUMP wordmark, from the original brand artwork (traced out of the supplied
 * logo PNG, ivory keyed to transparency). Using the artwork rather than a font
 * means we match the brand exactly without needing the Horizon licence installed.
 */
export default function Wordmark({ className, label }: { className?: string; label?: string }) {
  return (
    <span className={className}>
      <img src={wordmark} alt="" aria-hidden="true" />
      <span className="sr-only">{label ?? 'BUMP'}</span>
    </span>
  )
}
