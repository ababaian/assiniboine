#!/bin/bash

# getContig.bash Logan Script
# Dependencies: parallel (the GNU one), seqkit

# USAGE FUNCTION ===============================================================
function usage {
  echo ""
  echo "Usage: ./getContig.bash -i <SRRxxx_ContigNNN> -o <output_file>"
  echo ""
  echo "    Execution parameters"
  echo "    -f    File with contig ID list"
  echo "            use /dev/stdin to read from STDIN"
  echo "    -i    Input contig ID"
  echo "          can be a sequence of IDs, separated by spaces"
  echo "    -n    Number of threads to use (when using -f)"
  echo "            defaults to 8"
  echo "    -o    Output file"
  echo "            if not specified, prints to STDOUT"
  echo "    -s    SRR file to load contigs from"
  echo "            if specified, it will *only* fetch this one assembly file"
  echo "            and look for matching contig IDs inside of it;"
  echo "            if not specified, gets it from the first contig ID"
  echo ""
  echo "    Sequence parameters"
  echo "    -r    Reverse complement DNA sequence"
  echo ""
  echo "    Output 1: <SRRxxx_ContigNNN>.fa"
  echo "    Output 2: Sequence print to STDOUT"
  echo ""
  echo "ex: ./getContig.bash -i 'DRR286033_35087'"
  echo ""
  echo "Make sure the script is executable (chmod a+x getContig.bash),"
  echo "as it may need to call itself at times."
  exit 1
}

# INITIALIZE ===================================================================
FILE_CONTIG_ID_LIST=""
INPUT_CONTIG_ID=""
NUMBER_OF_THREADS=8
OUTPUT_FILE="&1"
REVERSE_COMPLEMENT=0
SRR_ID=""

while getopts "f:hi:n:o:rs:" OPT; do
  case $OPT in
    f ) # contig ID list
      FILE_CONTIG_ID_LIST="$OPTARG"
      ;;
    h ) # show help
      usage
      ;;
    i ) # input contig ID
      INPUT_CONTIG_ID="$OPTARG"
      ;;
    n ) # number of threads
      NUMBER_OF_THREADS="$OPTARG"
      ;;
    o ) # output file
      OUTPUT_FILE="$OPTARG"
      ;;
    r ) # reverse complement sequence
      REVERSE_COMPLEMENT=1
      ;;
    s ) # SRR ID file
      SRR_ID="$OPTARG"
      ;;
    \? ) # unrecognized option
      echo "Parameter not recognized: $OPTARG" 1>&2
      usage
      ;;
    : )
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      usage
      ;;
  esac
done
shift $((OPTIND -1))

if [ -z "$FILE_CONTIG_ID_LIST" ] && [ -z "$INPUT_CONTIG_ID" ]; then
    echo "Error: Missing required parameters."
    usage
fi

if [ -z "$SRR_ID" ]; then
  # Extract SRR_ID from INPUT_CONTIG_ID
  SRR_ID="${INPUT_CONTIG_ID%%_*}"
fi

# SCRIPT =======================================================================

# A list of contig IDs ...
if [ -n "$FILE_CONTIG_ID_LIST" ]; then
  if [ ! -f "$FILE_CONTIG_ID_LIST" ] && [ "$FILE_CONTIG_ID_LIST" != "/dev/stdin" ]; then
      echo "Error: File '$FILE_CONTIG_ID_LIST' not found."
      exit 1
  fi

  # Leaving this for reference, this is how we call all the lines in the file
  # without the fancy SRR single-fetch optimization
  # echo sed \'s/.*/.\\\/$0 -i \&/\' $FILE_CONTIG_ID_LIST \
  #   $( [ $REVERSE_COMPLEMENT = 0 ] && echo "" || echo "| sed 's/.*/& -r/'" ) \
  #   \| parallel -j $NUMBER_OF_THREADS -k \
  #   \>$OUTPUT_FILE \
  #   | bash

  # Craft a sequence of getContig invocations where all the contig IDs are
  # grouped and called together 
  declare -A FILE_CONTIG_ID_DICTIONARY

  while IFS= read -r LINE; do
    _SRR_ID="${LINE%%_*}"

    FILE_CONTIG_ID_DICTIONARY[$_SRR_ID]=${FILE_CONTIG_ID_DICTIONARY[$_SRR_ID]}$( [ -z "${FILE_CONTIG_ID_DICTIONARY[$_SRR_ID]}" ] && echo "" || echo " " )$LINE
  done < $FILE_CONTIG_ID_LIST

  # Don't ask how, this thing just works ...
  echo echo -e \"$(echo $(for KEY in "${!FILE_CONTIG_ID_DICTIONARY[@]}"; do
    echo -n "./$0 -i '${FILE_CONTIG_ID_DICTIONARY[$KEY]}'$( [ $REVERSE_COMPLEMENT = 0 ] && echo "" || echo " -r" )\n"
  done))\" \
    \| parallel -j $NUMBER_OF_THREADS -k \
    \>$OUTPUT_FILE \
    | bash
# ... otherwise, process a single contig ID
else
  echo Extracting contig [$INPUT_CONTIG_ID] from library [$SRR_ID]. \
    $( [ $REVERSE_COMPLEMENT = 0 ] && echo "" || echo " Reverse complement." ) >&2

  echo aws s3 cp s3://logan-pub/c/$SRR_ID/$SRR_ID.contigs.fa.zst - \
    \| zstd -dc - \
    \| seqkit grep -p ^${INPUT_CONTIG_ID// /\$ -p ^}\$ -r - \
    $( [ $REVERSE_COMPLEMENT = 0 ] && echo "" || echo "| seqkit seq --quiet -t dna -pr - | sed 's/\(^>.*\)/\1 [RC]/g' -" ) \
    \>$OUTPUT_FILE \
    | bash
fi