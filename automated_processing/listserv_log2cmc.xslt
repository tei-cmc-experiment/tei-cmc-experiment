<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:wf="http://www.wwp.northeastern.edu/ns/functions"
  xmlns:tmp="http://www.wwp.neu.edu/temp/ns"
  xmlns:array="http://www.w3.org/2005/xpath-functions/array"
  xmlns:map="http://www.w3.org/2005/xpath-functions/map"
  xmlns:tei="http://www.tei-c.org/ns/1.0"
  xmlns:xi="http://www.w3.org/2001/XInclude"
  xmlns:stxi="http://www.wwp.neu.edu/temp/ns"
  exclude-result-prefixes="#all"
  version="3.0">

  <!-- output debug msgs and intermediate files? -->
  <xsl:param name="debug" select="false()" static="yes" as="xs:boolean"/>
  <!-- output one file (a <TEI>) for each mailpiece, or one file (a <TEI>) for each mailpiece,
       plus a driver file (a <teiCorpus>) to link them together? -->
  <xsl:param name="split" select="false()" static="yes" as="xs:boolean"/>
  <!-- where to find the input file -->
  <xsl:param name="inputFilePath" select="'/tmp/TEI-L.txt'" as="xs:string"/>
  <!-- short version thereof for use in output files -->
  <xsl:variable name="inputFileName" select="tokenize( $inputFilePath, '/')[ last() ]"/>
  <!-- input file w/o extension is likely the name of the LISTSERV list we are archiving -->
  <xsl:param name="listName" select="replace( $inputFileName, '^(.*)\.[a-z]+$', '$1')"/>
  <!-- filename of this stylesheet -->
  <xsl:variable name="myFullName" select="tokenize( static-base-uri(), '/')[ last() ]"/>
  <!-- same sans extension for use in intermediate debugging filenames -->
  <xsl:param name="myName" select="$myFullName => replace('\.xslt?$','')"/>
  <!-- construct output file path; note that “STDOUT”, “stdout”, or
       “-” means to write to standard output as usual -->
  <xsl:param name="outputFilePath" as="xs:string"
             select="if (ends-with( $inputFilePath, '.txt') )
                     then replace( $inputFilePath, '\.txt$', '.xml')
                     else '/tmp/'||$myName||'_OUTPUT.xml'"/>
  
  <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
  <xsl:namespace-alias stylesheet-prefix="stxi" result-prefix="xi"/>
  <xsl:mode name="rudimentary2basic" on-no-match="shallow-copy"/>
  <xsl:mode name="addStructure"      on-no-match="shallow-copy"/>
  <xsl:mode name="addNamespace"      on-no-match="shallow-copy"/>
  <xsl:mode name="multipart"         on-no-match="shallow-copy"/>
  <xsl:mode name="record2field"      on-no-match="shallow-copy"/>
  <xsl:mode name="personography"     on-no-match="shallow-copy"/>
  <xsl:mode name="splitout"          on-no-match="shallow-copy"/>
  <xsl:mode name="singleout"         on-no-match="shallow-copy"/>
  
  <!-- General purpose (as opposed to phase-specific) subroutines and data structures -->
  <xsl:template name="maybeWriteDebugFile">
    <xsl:param name="mostRecentPass"/>
    <xsl:param name="tree" as="item()*"/>
    <xsl:if test="$debug">
      <xsl:variable name="dbgFN"
                    select="'/tmp/'
                            ||$myName
                            ||'_'
                            ||$inputFileName
                            ||'_post-pass_'
                            ||$mostRecentPass
                           "/>
      <xsl:result-document href="{$dbgFN}.xml">
        <debug of="{$myFullName}" post-pass="{$mostRecentPass}" input="{$inputFilePath}" at="{current-dateTime()}">
          <xsl:sequence select="$tree"/>
        </debug>
      </xsl:result-document>
    </xsl:if>
  </xsl:template>
  
  <!--
    Set up a key to normalize header fields as they occur in our dataset to values
    per https://www.iana.org/assignments/message-headers/message-headers.xhtml.
    Note that it would be more sensible to change all the keys to all lower
    case, in which case we would need fewer map entries and this routine would
    be more portable. But (for now) I prefer this because it also documents
    the variety in the input data set.
  -->
  <xsl:variable name="normalizeField" as="map(xs:string,xs:string)">
    <xsl:map>
      <xsl:map-entry key="'Comments'" select="'Comments'"/>
      <xsl:map-entry key="'Content-Description'" select="'Content-Description'"/>
      <xsl:map-entry key="'Content-Disposition'" select="'Content-Disposition'"/>
      <xsl:map-entry key="'Content-disposition'" select="'Content-Disposition'"/>
      <xsl:map-entry key="'Content-ID'" select="'Content-ID'"/>
      <xsl:map-entry key="'Content-id'" select="'Content-ID'"/>
      <xsl:map-entry key="'Content-Language'" select="'Content-Language'"/>
      <xsl:map-entry key="'Content-Transfer-Encoding'" select="'Content-Transfer-Encoding'"/>
      <xsl:map-entry key="'Content-transfer-encoding'" select="'Content-Transfer-Encoding'"/>
      <xsl:map-entry key="'Content-Type'" select="'Content-Type'"/>
      <xsl:map-entry key="'Content-type'" select="'Content-Type'"/>
      <xsl:map-entry key="'Date'" select="'Date'"/>
      <xsl:map-entry key="'From'" select="'From'"/>
      <xsl:map-entry key="'In-Reply-To'" select="'In-Reply-To'"/>
      <xsl:map-entry key="'Message-ID'" select="'Message-ID'"/>
      <xsl:map-entry key="'MIME-Version'" select="'MIME-Version'"/>
      <xsl:map-entry key="'MIME-version'" select="'MIME-Version'"/>
      <xsl:map-entry key="'Mime-Version'" select="'MIME-Version'"/>
      <xsl:map-entry key="'Mime-version'" select="'MIME-Version'"/>
      <xsl:map-entry key="'Organization'" select="'Organization'"/>
      <xsl:map-entry key="'Reply-To'" select="'Reply-To'"/>
      <xsl:map-entry key="'Sender'" select="'Sender'"/>
      <xsl:map-entry key="'Subject'" select="'Subject'"/>
      <xsl:map-entry key="'X-cc'" select="'X-cc'"/>
    </xsl:map>
  </xsl:variable>
  
  
  <!--
    ************************
    main routine starts here
    ************************
  -->
  <xsl:template name="xsl:initial-template" match="/">

    <!--
      This is a standard micropipeline along with the possibility of
      writing out the results of each stage save the last to a debug-
      ging output file in /tmp/.
    -->
    
    <!-- Read input file as plain text, as sequence of lines -->
    <xsl:variable name="IN" select="unparsed-text-lines( $inputFilePath )"/>

    <!-- Phase 1: convert plain text to rudimentary XML -->
    <xsl:message select="'info: phase 1 = plain text to rudimentary XML'"/>
    <xsl:variable name="phase1" as="element(mailPieces_rudimentary)">
      <xsl:call-template name="log2rudimentary">
        <xsl:with-param name="IN" select="$IN"/>
      </xsl:call-template>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'log2rudimentary'"/>
      <xsl:with-param name="tree" select="$phase1"/>
    </xsl:call-template>

    <!-- Phase 2: split multipart mailpieces into multiple parts 
    <xsl:message select="'info: phase 2 = chop up multipart'"/>
    <xsl:variable name="phase2" as="element(mailPieces_rudimentary)+">
      <xsl:apply-templates select="$phase1" mode="multipart"/>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'multipart'"/>
      <xsl:with-param name="tree" select="$phase2"/>
    </xsl:call-template>  MOVING THIS PIPE SECTION -->
    
    <!-- Phase 3: convert rudimentary to basic TEI-like elements -->
    <xsl:message select="'info: phase 3 = rudimentary to basic XML'"/>
    <xsl:variable name="phase3" as="element(mailPieces_basic)">
      <mailPieces_basic>
        <xsl:apply-templates select="$phase1" mode="rudimentary2basic"/>
      </mailPieces_basic>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'rudimentary2basic'"/>
      <xsl:with-param name="tree" select="$phase3"/>
    </xsl:call-template>
    
    <!-- Phase will-be-3: split multipart mailpieces into multiple parts -->
    <xsl:message select="'info: phase will-be-3 = divvy multipart post into multiple posts'"/>
    <xsl:variable name="phase3" as="element(mailPieces_basic)">
      <xsl:apply-templates select="$phase3" mode="splitParts"/>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'splitParts'"/>
      <xsl:with-param name="tree" select="$phase3"/>
    </xsl:call-template>
    
    <!-- Phase 4: add TEI structure -->
    <xsl:message select="'info: phase 4 = basic XML to near-TEI'"/>
    <xsl:variable name="phase4" as="element(teiCorpus)">
      <xsl:apply-templates select="$phase3" mode="addStructure"/>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'addStructure'"/>
      <xsl:with-param name="tree" select="$phase4"/>
    </xsl:call-template>

    <!-- Phase 5: personography -->
    <xsl:message select="'info: phase 5 = addd personography'"/>
    <xsl:variable name="phase5" as="element(teiCorpus)">
      <xsl:apply-templates select="$phase4" mode="personography"/>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'personography'"/>
      <xsl:with-param name="tree" select="$phase5"/>
    </xsl:call-template>

    <!-- Phase 6: final TEI-ification: add TEI namespace, and (at least for
         now) turn <line>-encoded lines into <lb>-divided text inside <ab>. -->
    <xsl:message select="'info: phase 6 = TEI-ification'"/>
    <xsl:variable name="phase6" as="element(tei:teiCorpus)">
      <xsl:apply-templates select="$phase5" mode="addNamespace"/>
    </xsl:variable>
    <xsl:call-template name="maybeWriteDebugFile">
      <xsl:with-param name="mostRecentPass" select="'addNamespace'"/>
      <xsl:with-param name="tree" select="$phase6"/>
    </xsl:call-template>
    
    <!-- Phase 7: output -->
    <xsl:choose>
      <xsl:when test="$split">
        <xsl:message select="'info: phase 7 = split output'"/>
        <xsl:apply-templates select="$phase6" mode="splitout"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:message select="'info: phase 7 = single output'"/>
        <xsl:variable name="phase7" as="element(tei:teiCorpus)">
          <xsl:apply-templates select="$phase6" mode="singleout"/>
        </xsl:variable>
        <xsl:choose>
          <xsl:when test="$outputFilePath = ('STDOUT','stdout','-')">
            <xsl:message select="'WARNING: @who attrs need to have paths corrected.'"/>
            <xsl:sequence select="$phase7"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:result-document href="{$outputFilePath}">
              <xsl:sequence select="$phase7"/>
            </xsl:result-document>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <!-- ********* phase 1, log2rudimentary ********* -->
  <xsl:template name="log2rudimentary">
    <xsl:param name="IN" as="xs:string+"/>
    <mailPieces_rudimentary>
      <xsl:for-each-group select="$IN" group-starting-with=".[matches( ., '^=========================================================================$')]">
        <xsl:variable name="n" select="format-integer( position(), '00000')"/>
        <xsl:variable name="lines" select="current-group()" as="xs:string+"/>
        <xsl:variable name="numLines" select="count($lines)"/>
        <xsl:choose>
          <xsl:when test="$numLines le 1">
            <xsl:message select="'debug: post #'||$n||' ignored, less than 2 lines'"/>
          </xsl:when>
          <xsl:when test="$numLines le 6">
            <xsl:message select="'debug: post #'||$n||' suspiscious, only '||$numLines||' lines'"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:message select="'debug: post #'||$n||' with '||$numLines||' lines'" use-when="$debug"/>
            <mailPiece n="{$n}" max="{$numLines}" xml:id="{$inputFileName||'_msg_'||$n}">
              <xsl:call-template name="mail2xml">
                <xsl:with-param name="lines" select="$lines"/>
              </xsl:call-template>
            </mailPiece>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each-group>
    </mailPieces_rudimentary>
  </xsl:template>

  <xsl:template name="mail2xml" as="element()+">
    <xsl:param name="lines" as="xs:string+"/>
    <!-- Get the index # of the first line that is either null or contains only a space. -->
    <xsl:variable name="firstNull" as="xs:integer"
      select="sort( ( index-of( $lines, '&#x20;'), index-of( $lines, '') ) )[1]"/>
    <!-- Lines before that first null are the SMTP header lines -->
    <xsl:variable name="headerLines" select="$lines[ position() le $firstNull ]"/>
    <!-- Lines after that first null line are the body (unless multipart, handled by next phase) -->
    <xsl:variable name="bodyLines" select="$lines[ position() gt $firstNull ]"/>
    <mailHeader>
      <xsl:variable name="headerRecords" select="wf:decontinue( $headerLines )" as="element(line)+"/>
      <xsl:apply-templates select="$headerRecords" mode="record2field"/>
    </mailHeader>
    <mailBody>
      <xsl:for-each select="$bodyLines">
        <line n="{position()}"><xsl:sequence select="."/></line>
      </xsl:for-each>
    </mailBody>
  </xsl:template>
  
  <!--
    Given a sequence of text lines, return a sequence of <line>
    elements, one for each input line, EXCEPT that a “continuation
    line” — an intput text line that starts with whitespace — is
    apppended (after a space character) to the content of the
    <line> that represents the previous input line instead of
    being put in a <line> of its own.
  -->
  <xsl:function name="wf:decontinue" as="element(line)+">
    <xsl:param name="inputTextLines" as="xs:string+"/>
    <!--
      First convert each text line into a <line> element; add a @break attribute 
      iff the content does NOT start with whitespace.
    -->
    <xsl:variable name="lineElements" as="element(line)+">
      <xsl:for-each select="$inputTextLines">
        <line>
          <xsl:if test="matches( ., '^\S')">
            <xsl:attribute name="break" select="true()"/>
          </xsl:if>
          <xsl:sequence select="."/>
        </line>
      </xsl:for-each>
    </xsl:variable>
    <!--
      Now group the sequence of <line> elements we just created by the presence of
      the @break attribute. That is, every <line> that has a @break starts a new
      group; thus those that do not have a @break are part of the group with the
      preceding <line> that did have a @break.
    -->
    <xsl:for-each-group select="$lineElements" group-starting-with="line[@break]">
      <!--
        This is a group of a line that starts with a non-whitespace character and
        zero or more lines that do start with a whitespace character. Concatonate
        them into one <line>.
      -->
      <line><xsl:sequence select="string-join( current-group(), '&#x20;') => normalize-space()"/></line>
    </xsl:for-each-group>
  </xsl:function>
   
  <xsl:template match="*" mode="record2field" as="element()">
    <!--
      If the content of the context node (an element) looks like an SMTP header
      field, return an element whose GI is the name of the field, and whose content
      is the value of the field. If it does not look like an SMTP header, just
      return it.
    -->
    <xsl:choose>
      <xsl:when test="matches( string(.), '^\S+:')">
        <xsl:variable name="fieldName" select="replace( string(.), '^(\S+):\s*.*$','$1')" as="xs:string"/>
        <xsl:variable name="fixedFieldName" as="xs:string?"
                      select="if (starts-with($fieldName,'X-') )
                              then $fieldName
                              else $normalizeField($fieldName)"/>
        <xsl:variable name="fieldContent" select="replace( string(.), '^\S+:\s+(.*)$','$1')"/>
        <!--
          Fail if the field name is not a legal XML name. (This will happen if either
          an X- field name has illegal characters in its name after the X-, or, much
          more likely, when a field name that does not start with X- is not listed in
          the $normalizeField map — the map returns null which fails as an XML Name
          big time.
        -->
        <xsl:try>
          <xsl:element name="{$fixedFieldName}">
            <xsl:if test="$fixedFieldName ne $fieldName">
              <xsl:attribute name="orig" select="$fieldName"/>
            </xsl:if>
            <xsl:sequence select="$fieldContent"/>
          </xsl:element>
          <xsl:catch>
            <xsl:message terminate="yes" select="'Fatal: '||$fieldName||' freakin’ failed.'"/>
          </xsl:catch>
        </xsl:try>
      </xsl:when>
      <xsl:otherwise>
        <!--
          It does not look like a field, so just copy it and process its children.
          (Thus copying it.)
        -->
        <xsl:copy>
          <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <!-- ********* phase used-to-be-2, multipart — currently unused, see splitPart ********* -->
  <xsl:template match="mailPiece[ matches( mailHeader/Content-Type!string(), 'multipart/') ]" mode="multipart">
    <xsl:variable name="content_type" select="normalize-space(./mailHeader/Content-Type)" as="xs:string"/>
    <xsl:variable name="boundary" as="xs:string"
                  select="replace( $content_type, '^.*boundary=&quot;?([^;&quot;]+)&quot;?(;.*)?$','$1')"/>
    <xsl:variable name="boundryLine" select="'--'||$boundary" as="xs:string"/>
    <xsl:variable name="partNumAdjust" as="xs:integer"
                  select="if ( mailBody/line[1]/string() eq $boundryLine )
                          then 0 else -1"/>
    <xsl:for-each-group select="./mailBody/line"
      group-starting-with=".[ string(.) eq $boundryLine ]">
      <mailPiece debug-multipart="{position() + $partNumAdjust}">
        <xsl:apply-templates select="ancestor::mailPiece/@*" mode="#current"/>
        <xsl:attribute name="xml:id" select="ancestor::mailPiece/@xml:id||'_'|| position() + $partNumAdjust"/>
        <!-- <xsl:message select="'debug: processing grp ' -->
        <!--   ||ancestor::mailPiece/@xml:id||'_'||position() -->
        <!--   ||' which has '||count(current-group())||' items, 1st is line ' -->
        <!--   ||current-group()[1]/@n||' and starts with ' -->
        <!--   ||substring( current-group()[1], 1, 32 )||'.'"/> -->
        <xsl:attribute name="debug-boundary" select="$boundary"/>
        <xsl:variable name="firstEmpty" as="xs:integer">
          <xsl:choose>
            <xsl:when test="current-group()[ normalize-space(.) eq '']">
              <xsl:sequence select="current-group()[ normalize-space(.) eq ''][1]/@n cast as xs:integer"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:sequence select="0"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <!-- If the first member of this group is the boundary line, then
             it is a normal group, the first empty line divides header info
             from body data. But if not, it is the 1st group and all lines
             are body data. -->
        <xsl:variable name="partHeader" as="element(line)*">
          <xsl:choose>
            <xsl:when test="current-group()[1]/string() eq $boundryLine">
              <xsl:sequence select="current-group()[ @n cast as xs:integer lt $firstEmpty ]"/>
            </xsl:when>
            <xsl:otherwise/>
          </xsl:choose>
        </xsl:variable>
        <xsl:variable name="partRest" as="element(line)*">
          <xsl:choose>
            <xsl:when test="current-group()[1]/string() eq $boundryLine">
              <xsl:sequence select="current-group()[ @n cast as xs:integer gt $firstEmpty ]"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:sequence select="current-group()"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <mailHeader>
          <xsl:apply-templates select="../../mailHeader/@*" mode="#current"/>
          <xsl:apply-templates select="../../mailHeader/*" mode="#current"/>
          <xsl:variable name="partHeaderRecs">
            <xsl:choose>
              <xsl:when test="count( $partHeader ) gt 1">
                <xsl:sequence select="wf:decontinue( $partHeader[ position() gt 1 ] )"/>
              </xsl:when>
              <xsl:otherwise>
                <xsl:sequence select="$partHeader"/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:variable>
          <!-- <xsl:message select="'debug: partHeader('||count($partHeader)||')='||string-join($partHeader/@n,', ')"/> -->
          <!-- <xsl:message select="'debug: partRest('||count($partRest)||')='||string-join($partRest/@n,', ')"/> -->
          <xsl:apply-templates select="$partHeaderRecs" mode="record2field"/>
        </mailHeader>
        <mailBody>
          <xsl:apply-templates select="../@*" mode="#current"/>
          <xsl:apply-templates select="$partRest[ position() ne last()  or  string(.) ne concat( $boundryLine, '--') ]" mode="#current"/>
        </mailBody>
      </mailPiece>
    </xsl:for-each-group>
  </xsl:template>
  
  <!-- ********* phase was-3-now-2, rudimentary2basic ********* -->
  <xsl:template match="mailPieces_rudimentary" mode="rudimentary2basic">
    <xsl:apply-templates select="@*|node()" mode="#current"/>
  </xsl:template>
  <xsl:template match="mailHeader" mode="rudimentary2basic">
    <xsl:variable name="postNumStr" select="' posting '||format-integer( xs:integer(../@n), '0')"/>
    <teiHeader>
      <fileDesc>
        <titleStmt>
          <title>
            <xsl:sequence select="$listName||$postNumStr"/>
          </title>
        </titleStmt>
        <publicationStmt>
          <ab>Currently an experimental document not intended
            for publication. That said, the original source was
            published as part of a public mailing list, so this
            document similarly is publicly available.</ab>
        </publicationStmt>
        <sourceDesc>
          <ab type="desc">The source text file was (or at least should have been)
            a log file from a LISTSERV mailing list.</ab>
          <ab type="filepath"><xsl:sequence select="$inputFilePath"/></ab>
        </sourceDesc>
      </fileDesc>
      <encodingDesc>
        <appInfo>
          <application ident="{$myFullName}" version="0.1" xsl:expand-text="yes">
            <desc>This file generated {current-dateTime()} by {static-base-uri()},
              a program intended to convert LISTSERV logs (i.e., an archive of
              postings to a LISTSERV mailing list) to TEI, using {$inputFilePath} as input.</desc>
          </application>
        </appInfo>
      </encodingDesc>
      <profileDesc>
        <correspDesc>
          <correspContext>
            <!-- In two cases there are multiple email addrs in Reply-To field -->
            <xsl:variable name="replyTo" as="xs:string+">
              <xsl:for-each select="tokenize( Reply-To/string() => normalize-space(), ',&#x20;?')">
                <xsl:sequence select="'mailto:'||wf:extract_sender(.)"/>
              </xsl:for-each>
            </xsl:variable>
            <ptr type="reply-to" target="{string-join($replyTo,'&#x20;')}"/>
            <xsl:if test="In-Reply-To">
              <ref type="in-reply-to"><xsl:sequence select="In-Reply-To/string()"/></ref>
            </xsl:if>
          </correspContext>
          <correspAction type="relayed">
            <email><xsl:sequence select="wf:extract_sender(Sender/string())"/></email>
            <date><xsl:sequence select="Date/string()"/></date>
          </correspAction>
          <xsl:where-populated>
            <correspAction type="sent">
              <xsl:where-populated>
                <idno type="message-id"><xsl:sequence select="Message-ID/string()"/></idno>
              </xsl:where-populated>
              <xsl:where-populated>
                <orgName><xsl:sequence select="Organization"/></orgName>
              </xsl:where-populated>
            </correspAction>
          </xsl:where-populated>
          <xsl:where-populated>
            <note type="Comments"> <xsl:sequence select="Comments/string()"/> </note>
          </xsl:where-populated>
        </correspDesc>
      </profileDesc>
      <xenoData>
        <xsl:apply-templates mode="#current"/>
      </xenoData>
    </teiHeader>
  </xsl:template>

  <xsl:template match="mailHeader//*" mode="rudimentary2basic">
    <xsl:element name="tmp:{local-name(.)}">
      <xsl:apply-templates mode="#current"/>
    </xsl:element>
  </xsl:template>

  <xsl:template match="mailBody" mode="rudimentary2basic">
    <text>
      <body>
        <xsl:variable name="from" select="../mailHeader/From/string()" as="xs:string"/>
        <xsl:variable name="email" select="wf:parse_from_field($from)[2]"/>
        <xsl:variable name="contentType" as="xs:string?"
          select="../mailHeader/Content-Type[not( matches( .,'multipart/','i') ) ]/string()"/>
        <xsl:variable name="mimeType" as="xs:string"
          select="substring-before( $contentType, '&#x20;') => lower-case()"/>
        <xsl:variable name="who" as="xs:string"
          select="if ($split)
                  then $outputFilePath||'#'||wf:email2id( $email )
                  else '#'||wf:email2id( $email )"/>
        <post who="{$who}" when="{ wf:date2when(../mailHeader/Date/normalize-space() ) }">
          <xsl:where-populated>
            <xsl:attribute name="type" select="$mimeType"/>
          </xsl:where-populated>
          <head type="subject"><xsl:sequence select="../mailHeader/Subject/string()"/></head>
          <xsl:apply-templates mode="#current"/>
        </post>
      </body>
    </text>
  </xsl:template>
  
  <xsl:function name="wf:extract_sender" as="xs:string">
    <xsl:param name="sender" as="xs:string"/>
    <xsl:sequence select="replace( $sender, '^.[^&lt;]*&lt;([^>]+)>$','$1')"/>
  </xsl:function>
  
  <xsl:variable name="monthName2MM" as="map(xs:string, xs:string)">
    <xsl:map>
      <xsl:map-entry key="'Jan'" select="'01'"/>
      <xsl:map-entry key="'Feb'" select="'02'"/>
      <xsl:map-entry key="'Mar'" select="'03'"/>
      <xsl:map-entry key="'Apr'" select="'04'"/>
      <xsl:map-entry key="'May'" select="'05'"/>
      <xsl:map-entry key="'Jun'" select="'06'"/>
      <xsl:map-entry key="'Jul'" select="'07'"/>
      <xsl:map-entry key="'Aug'" select="'08'"/>
      <xsl:map-entry key="'Sep'" select="'09'"/>
      <xsl:map-entry key="'Oct'" select="'10'"/>
      <xsl:map-entry key="'Nov'" select="'11'"/>
      <xsl:map-entry key="'Dec'" select="'12'"/>
    </xsl:map>
  </xsl:variable>

  <!-- time zone potentially invalid abbreviation to time zone -->
  <xsl:variable name="tzia2TZ" as="map(xs:string, xs:string)">
    <xsl:map>
      <xsl:map-entry key="'BST'"  select="'+0100'"/>
      <!-- BST might also be Brazillian Summer Time (-2), Bangladesh
           Standard Time (+6), or Bougainville Standard Time (+11). -->
      <xsl:map-entry key="'CDT'"  select="'-0500'"/>
      <!-- CDT might also be Cuba Daylight Time (-4) -->
      <xsl:map-entry key="'CET'"  select="'+0100'"/>
      <xsl:map-entry key="'CST'"  select="'-0600'"/>
      <!-- CST might also be China Standard Time (+8) or
           Cuba Standard Time (-5) -->
      <xsl:map-entry key="'DNT'"  select="'+0200'"/>
      <!-- DNT is not a recognized time zone abbreviatio (per
           https://www.timeanddate.com/time/zones/). I am con-
           fident it is a Danish time zone, as the only 2 posts
           that use it were from an address ending in “.dh”
           from a name that sounds Dutch. -->
      <xsl:map-entry key="'EDT'"  select="'-0400'"/>
      <xsl:map-entry key="'EST'"  select="'-0500'"/>
      <xsl:map-entry key="'GMT'"  select="'Z'"/>
      <xsl:map-entry key="'GMT0BST'"  select="'Z'"/>
      <!-- I do not know what this means, but the only post using
           this was sent from Wales before DST had started that
           year. -->
      <xsl:map-entry key="'HAE'"  select="'-0400'"/>
      <xsl:map-entry key="'HKT'"  select="'+0800'"/>
      <xsl:map-entry key="'HNE'"  select="'-0500'"/>
      <xsl:map-entry key="'IST'"  select="'+0200'"/>
      <!-- IST might also be India Standard Time (+05:30)
           or Irish Standard Time (+1) -->
      <xsl:map-entry key="'KST'"  select="'+0900'"/>
      <xsl:map-entry key="'LCL'"  select="''"/>
      <!-- I presume LCL means local -->
      <xsl:map-entry key="'MDT'"  select="'-0600'"/>
      <xsl:map-entry key="'MET'"  select="'+0100'"/>
      <!-- MET is not a recognized time zone abbreviation (per
           https://www.timeanddate.com/time/zones/). I am con-
           fident it is a Dutch time zone, as all the posts
           that use it were from an address ending in “.nl”
           from a name that sounds Dutch. -->
      <xsl:map-entry key="'METDST'"  select="'+0200'"/>
      <!-- METDST is not a recognized time zone abbreviation (per
           https://www.timeanddate.com/time/zones/). I am con-
           fident it is a Dutch time zone, as the only post
           that uses it was from an address ending in “.nl”
           during a period that was in DST for the Netherlands. -->
      <xsl:map-entry key="'MEZ'"  select="'+0100'"/>
      <xsl:map-entry key="'MST'"  select="'-0700'"/>
      <!-- MST might also be Malaysia Standard Time (+8) -->
      <xsl:map-entry key="'MSZ'"  select="'+0200'"/>
      <!-- MSZ is not a recognized time zone abbreviation (per
           https://www.timeanddate.com/time/zones/). I think it
           is DST in Germany, as I recognize I recognize on of
           the posters as being German, and another is a German-
           sounding name. -->
      <xsl:map-entry key="'N'"    select="'-0100'"/>
      <xsl:map-entry key="'O'"    select="'-0200'"/>
      <xsl:map-entry key="'PDT'"  select="'-0700'"/>
      <xsl:map-entry key="'PLT'"  select="'-0800'"/>
      <!-- PLT is not a recognized time zone abbreviation (per
           https://www.timeanddate.com/time/zones/). I am not
           at all sure about this, but the only 1 posting came
           from WSUVM1, which was probably from the University
           of Washington (during the summer). -->
      <xsl:map-entry key="'PST'"  select="'-0800'"/>
      <!-- PST might also mean Phillipine Standard Time (+8)
           or Pitcairn Standard Time (-8). -->
      <xsl:map-entry key="'SET'"  select="'+0100'"/>
      <!-- SET is not a recognized time zone abbreviation (per
           https://www.timeanddate.com/time/zones/). I think it
           is standard time in Switzerland, because all posts
           using this are from CERNVM.BITNET, which was likely
           in Switzerland, and are not during summer time there. -->
      <xsl:map-entry key="'TZONE'"  select="'+0100'"/>
      <!-- Obviously, TZONE is not a recognized time zone abbreviation.
           I think it is standard time in Germany, because the only post
           using it is from an address ending in “.de” when DST was not
           in effect. -->
    </xsl:map>
  </xsl:variable>

  <xsl:function name="wf:date2when" as="xs:string">
    <xsl:param name="date" as="xs:string"/>
    <xsl:analyze-string select="$date"
      regex="^(Sun|Mon|Tue|Wed|Thu|Fri|Sat), ([0-9]+) (Jan|Feb|Mar|Apr|May|Ju[nl]|Aug|Sep|Oct|Nov|Dec)[a-z]* ([0-9]+) ([012][0-9]:[0-6][0-9]:[0-6][0-9]) (.+)$">
      <xsl:matching-substring>
        <xsl:variable name="one" select="regex-group(1)"/>
        <xsl:variable name="DD" select="regex-group(2) => xs:integer() => format-integer('##')"/>
        <xsl:variable name="MM" select="regex-group(3) => $monthName2MM()"/>
        <xsl:variable name="YYYY">
          <xsl:variable name="year" select="regex-group(4)"/>
          <xsl:sequence select="if ( string-length( $year ) eq 4 ) then $year else '19'||$year"/>
        </xsl:variable>
        <xsl:variable name="time" select="regex-group(5)"/>
        <xsl:variable name="tzi" select="regex-group(6) => upper-case()"/>
        <xsl:variable name="tz">
          <xsl:choose>
            <xsl:when test="matches( $tzi, '^[+-][0-9][0-9][0-9][0-9]$')">
              <xsl:sequence select="wf:colonize($tzi)"/>
            </xsl:when>
            <xsl:when test="matches( $tzia2TZ( $tzi ), '^[+-][0-9][0-9][0-9][0-9]$')">
              <xsl:sequence select="wf:colonize( $tzia2TZ( $tzi ) )"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:sequence select="$tzia2TZ( $tzi )"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:variable>
        <xsl:sequence select="$YYYY||'-'||$MM||'-'||$DD||'T'||$time||$tz"/>
      </xsl:matching-substring>
    </xsl:analyze-string>
  </xsl:function>
  
  <xsl:function name="wf:colonize" as="xs:string">
    <xsl:param name="plus_minus_hh_mm"/>
    <xsl:sequence select="substring( $plus_minus_hh_mm, 1, 3 )
                        ||':'
                        ||substring( $plus_minus_hh_mm, 4 ) "/>
  </xsl:function>
  
  <!-- phase new-3: splitParts -->
  <xsl:template match="mailPiece[ teiHeader/xenoData/tmp:Content-Type[ matches( ., 'multipart/') ] ]" mode="splitParts">
    <xsl:variable name="content_type" select="normalize-space( teiHeader/xenoData/tmp:Content-Type)" as="xs:string"/>
    <xsl:variable name="boundary" as="xs:string"
      select="replace( $content_type, '^.*boundary=&quot;?([^;&quot;]+)&quot;?(;.*)?$','$1')"/>
    <xsl:variable name="boundryLine" select="'--'||$boundary" as="xs:string"/>
    <xsl:apply-templates select="teiHeader" mode="#current"/>
    <xsl:apply-templates select="text" mode="#current">
      <xsl:with-param name="boundryLine" select="$boundryLine" as="xs:string"/>
    </xsl:apply-templates>
  </xsl:template>
  
  <xsl:template match="post" mode="splitParts">
    <xsl:param name="boundryLine" as="xs:string"/>
    <xsl:for-each-group select="line" group-starting-with=".[ string(.) eq $boundryLine ]">
      <xsl:variable name="partNumAdjust" as="xs:integer"
                    select="if ( line[1]/string() eq $boundryLine ) then 0 else -1"/>
      <xsl:variable name="partNumStr" select="format-integer( position()+$partNumAdjust, '00')"/>
      <post xml:id="{ancestor::mailPiece/@xml:id||'_'||$partNumStr}">
        
      </post>
    </xsl:for-each-group>
  </xsl:template>
  
  <!-- ********* phase 4: addStructure ********* -->
  <xsl:template match="mailPieces_basic" mode="addStructure">
    <xsl:variable name="mailPieceBYmsgid" as="map( xs:string, xs:string )">
      <xsl:map>
        <xsl:for-each select="mailPiece[ not( @debug-multipart ) or @debug-multipart cast as xs:integer eq 1]
                             /teiHeader/profileDesc/correspDesc//idno[@type eq 'message-id']">
          <xsl:sort select="string(.)"/>
          <xsl:choose>
            <xsl:when test=". =  (: need sequence operator because once in while there are 2 w/ same ID :)
              ancestor::mailPiece
              /preceding-sibling::mailPiece[ not( @debug-multipart ) or @debug-multipart cast as xs:integer eq 1]
              /teiHeader/profileDesc/correspDesc//idno[ @type eq 'message-id']!string()">
              <xsl:if test="$debug">
                <xsl:message select="'debug: dropping msgid '||position()||' (after sorting).'" use-when="$debug"/>
              </xsl:if>
            </xsl:when>
            <xsl:otherwise>
              <xsl:if test="$debug">
                <xsl:message select="'debug: try key='||.||' sel='||ancestor::mailPiece/@xml:id"/>
              </xsl:if>
              <xsl:map-entry key="string(.)" select="ancestor::mailPiece/@xml:id!string()"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
      </xsl:map>
    </xsl:variable>    
    <teiCorpus>
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:call-template name="corpusHeader"/>
      <xsl:apply-templates select="node()" mode="#current">
        <xsl:with-param name="mailPieceBYmsgid" select="$mailPieceBYmsgid"/>
      </xsl:apply-templates>
    </teiCorpus>
  </xsl:template>
  
  <xsl:template match="mailPiece" mode="addStructure">
    <xsl:param name="mailPieceBYmsgid" as="map( xs:string, xs:string )"/>
    <TEI>
      <xsl:apply-templates select="@* except @max|node()" mode="#current">
        <xsl:with-param name="mailPieceBYmsgid" select="$mailPieceBYmsgid" as="map( xs:string, xs:string )"/>
      </xsl:apply-templates>
    </TEI>
  </xsl:template>

  <xsl:template match="ref[ @type eq 'in-reply-to']" mode="addStructure">
    <xsl:param name="mailPieceBYmsgid" as="map( xs:string, xs:string )"/>
    <xsl:variable name="irtmid" select="."/><!-- in reply to message id -->
    <xsl:variable name="myTargets" select="$mailPieceBYmsgid( $irtmid )"/>
<!--    <xsl:variable name="myTargets" as="xs:string*"
      select="ancestor::mailPieces_basic
      /mailPiece
      /teiHeader
      /profileDesc
      /correspDesc
      //idno[@type eq 'message-id'][ . eq $irtmid ]/ancestor::mailPiece/@xml:id"/>
-->    <!-- Since we have already split multipart mailpieces into multiple
	 posts, the above may have selected multiple IDs. We have no way
	 of knowing which the user might prefer, so (at least for now)
	 just take the first that is not a prologue (i.e., a part
	 ‘0’). -->
    <xsl:variable name="myTarget" select="$myTargets[ not( ends-with( .,'_0') ) ][1]"/>
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:if test="$myTarget ne ''">
        <xsl:attribute name="target">
          <xsl:choose>
            <xsl:when test="$split">
              <xsl:sequence select="'./'||$myTarget||'.xml'"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:sequence select="'#'||$myTarget"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:attribute>
      </xsl:if>
      <xsl:apply-templates select="node()"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template name="corpusHeader">
    <teiHeader>
      <fileDesc>
        <titleStmt>
          <title><xsl:sequence select="$listName"/></title>
          <title type="sub">a corpus of <xsl:sequence select="count(mailPiece)"/> postings</title>
          <publicationStmt>
            <ab>Currently an experimental document not intended
              for publication. That said, the original source was
              published as part of a public mailing list, so this
              document similarly is publicly available.</ab>
          </publicationStmt>
          <sourceDesc xsl:expand-text="yes">
            <ab>Derived from source file {$inputFilePath}, which
              should be a log file from a LISTSERV mailing list.</ab>
          </sourceDesc>
        </titleStmt>
      </fileDesc>
      <encodingDesc>
        <appInfo>
          <application ident="{$myFullName}" version="0.1" xsl:expand-text="yes">
            This file generated {current-dateTime()} by {static-base-uri()}
            using {$inputFilePath} as input.
          </application>
        </appInfo>
      </encodingDesc>
    </teiHeader>
  </xsl:template>

  <!-- ********* phase 5: personography ********* -->
  <xsl:template match="teiCorpus" mode="personography">
    <xsl:variable name="all_persons" as="element(person)*">
      <xsl:apply-templates select="(TEI/teiHeader/xenoData)/(tmp:From|tmp:Reply-To)" mode="field2person"/>
    </xsl:variable>
    <xsl:variable name="sorted_persons" as="element(person)*">
      <xsl:for-each select="$all_persons">
        <xsl:sort select="@email"/>
        <xsl:copy-of select="."/>
      </xsl:for-each>
    </xsl:variable>
    <xsl:variable name="persons" as="element(person)*">
      <xsl:for-each-group select="$all_persons" group-by="@email">
        <person xml:id="{wf:email2id( current-grouping-key() )}">
          <xsl:for-each select="distinct-values( current-group()/ab/string() )">
            <xsl:variable name="parsed_from_field" select="wf:parse_from_field(.)"/>
            <xsl:variable name="name_ff" select="$parsed_from_field[1]"/>
            <xsl:variable name="email_ff" select="$parsed_from_field[2]"/>
            <xsl:where-populated>
              <name><xsl:value-of select="$name_ff"/></name>
            </xsl:where-populated>
            <xsl:if test="position() eq last()">
              <xsl:where-populated>
                <state><email><xsl:value-of select="$email_ff"/></email></state>
              </xsl:where-populated>
            </xsl:if>
          </xsl:for-each>
        </person>
      </xsl:for-each-group>
    </xsl:variable>
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="#current"/>
      <teiHeader>
        <xsl:apply-templates select="teiHeader/@*" mode="#current"/>
        <xsl:apply-templates select="teiHeader/node()" mode="#current"/>
        <profileDesc>
          <particDesc>
            <listPerson>
              <xsl:sequence select="$persons"/>
            </listPerson>
          </particDesc>
        </profileDesc>
      </teiHeader>
      <xsl:apply-templates select="TEI" mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="tmp:From|tmp:Reply-To" mode="field2person">
    <xsl:variable name="nfc" select="."/>
    <xsl:variable name="email"
      select="if ( contains( $nfc, '>') )
      then replace( $nfc, '^.*&lt;([^&lt;&gt;]+)&gt;$','$1')
      else $nfc
      "/>
    <person email="{lower-case( $email )}">
      <ab type="name_field_content"><xsl:sequence select="$nfc/string()"/></ab>
    </person>
  </xsl:template>
  
  <xsl:function name="wf:email2id">
    <xsl:param name="email" as="xs:string"/>
    <!-- replace characters not allowed in an XML Name with characters
         that are not allowed in an e-mail address. (Thus there can be
         no ambiguity in the return trip.) -->
    <xsl:variable name="almost_id" select="lower-case( $email )
         => replace( '@', '·＠·')
         => replace(':', '·：﹕·')
         => replace('!', '·ǃ·')
         => replace('\+', '·𝅄·')
         => replace('%', '·﹪·')
         => replace('/', '·𝆱·')
         => replace('~', '·𝆝·')"/>
    <!-- if addr does not start with a Letter or underscore, prepend
         a string that is not allowed in an e-mail address. -->
    <!-- (I have checked, all cases that are not Letter or underscore
         are digits; ‘7’ and ‘9’, to be precise.) -->
    <xsl:sequence select="if ( matches( substring( $almost_id, 1, 1 ), '^[0-9]') )
                          then concat('·', $almost_id )
                          else $almost_id"/>
  </xsl:function>
  
  <xsl:function name="wf:parse_from_field" as="xs:string+">
    <!-- The name is a bit of a pun: It means “parse things from the field
         value provided as the parameter”; but, also, because the field
         whose value is being sent as a parameter is often the “From:”
         field, it often means “parse the value of the From: field”. :-) -->
    <xsl:param name="nfc" as="xs:string"/><!-- name field contents -->
    <xsl:variable name="email" as="xs:string"
      select="if ( contains( $nfc, '>') )
              then replace( $nfc, '^.*&lt;([^&lt;&gt;]+)&gt;$','$1')
              else $nfc   "/>
    <xsl:variable name="name" as="xs:string"
      select="if ( contains( $nfc, '>') )
              then replace( $nfc, '^(.*)&lt;([^&lt;&gt;]+)&gt;$','$1')
              else ''   "/>
    <xsl:sequence select="( normalize-space($name), normalize-space($email) )"/>
  </xsl:function>
  
  <!-- ********* phase 6: add TEI namespace ********* -->
  <xsl:template match="*[ not( parent::xenoData ) ]" mode="addNamespace">
    <xsl:element name="{local-name(.)}" namespace="http://www.tei-c.org/ns/1.0">
      <xsl:apply-templates select="@*|node()" mode="#current"/>
    </xsl:element>
  </xsl:template>
  
  <xsl:template match="post/line" mode="addNamespace" priority="2">
    <xsl:text>&#x0A;          </xsl:text>
    <xsl:if test="xs:integer(@n) gt 1">
      <xsl:element name="lb" namespace="http://www.tei-c.org/ns/1.0">
        <xsl:attribute name="n" select="xs:integer(@n) -1"/>
      </xsl:element>
    </xsl:if>
    <xsl:value-of select="string(.)"/>
  </xsl:template>
  
  <!-- ********* phase 7, single out: generate a single corpus output file ********* -->
  <xsl:template match="tei:teiCorpus" mode="singleout">
    <xsl:copy>
      <xsl:namespace name="tmp" select="'http://www.wwp.neu.edu/temp/ns'"/>
      <xsl:namespace name="xi" select="'http://www.w3.org/2001/XInclude'"/>
      <xsl:apply-templates select="@*|node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>  
  
  <!-- ********* phase 7, splitout: generate 1 file for each input msg ********* -->
  <xsl:template match="tei:teiCorpus" mode="splitout">
    <xsl:result-document href="{replace( $outputFilePath, '\.xml', '_corpus.xml')}">
      <xsl:copy>
        <xsl:namespace name="tmp" select="'http://www.wwp.neu.edu/temp/ns'"/>
        <xsl:namespace name="xi" select="'http://www.w3.org/2001/XInclude'"/>
        <xsl:apply-templates select="@*|node()" mode="#current"/>
      </xsl:copy>
    </xsl:result-document>
  </xsl:template>
  
  <xsl:template match="tei:TEI" mode="splitout">
    <stxi:include href="{@xml:id}.xml"/>
    <xsl:result-document href="{ replace( $outputFilePath, '/[^/]+\.xml$', '/'||@xml:id||'.xml')}">
      <!--
        <xsl:copy-of select="."/> would work here, but we want explicit namespace
        declarations on the outermost <TEI> of the output, thus to avoid multiple
        declarations on the internal compoments, particularly the children of
        <xenoData>.
      -->
      <xsl:copy>
        <xsl:namespace name="tmp" select="'http://www.wwp.neu.edu/temp/ns'"/>
        <xsl:namespace name="xi" select="'http://www.w3.org/2001/XInclude'"/>
        <xsl:apply-templates select="@*|node()" mode="#current"/>
      </xsl:copy>
    </xsl:result-document>
  </xsl:template>
  
  <xsl:template match="@*[ starts-with( local-name(.), 'debug') ]" mode="splitout"/>

</xsl:stylesheet>
