  <!-- Except for class="jquery-ui-subaccordion-closed", all attributes of the accordion-related div elements can be generated during initialization of the page. However, the initialization takes up to 10 seconds and we want something reasonably nice to be visible as soon as possible. -->
  <div class="ui-accordion-header ui-helper-reset ui-state-default ui-corner-all" role="tab" aria-expanded="false" aria-selected="false" tabindex="-1"> <!-- start of {{language_name}} accordion row -->
    <span class="flagspan"><img class="flag" src="flags/svg/{{flag}}.svg" /></span>
    <span class="doublewidespan">{{language_name_short}}</span>
    <span class="widespan"><span class="hint--top hint--info" data-hint="{{treebanks|length}} treebank{% if treebanks|length > 1 %}s{% endif %}">{{treebanks|length}}</span></span>
    <span class="widespan"><span class="hint--top hint--info" data-hint="{{counts.token|tsepk}} tokens {{counts.word|tsepk}} words {{counts.node|tsepk}} nodes {{counts.tree|tsepk}} sentences">{{counts.word|tsepk(use_k=true)}}</span></span>
    <!-- English has so many genres that they no longer fit in doublewidespan. -->
    <span class="triplewidespan">{{genres|genre_filter|safe}}</span>
    <span class="triplewidespan">{{(language_family,language_genus)|family_filter|safe}}</span>
  </div> <!-- end of {{language_name}} accordion row -->

  <div class="ui-accordion-content ui-helper-reset ui-widget-content ui-corner-bottom" style="" role="tabpanel"> <!-- start of {{language_name}} accordion body -->
  <!--initial style="height:558.8px; display: none" would make the page a bit better before setup is done but the height of the subaccordions would not be measured correctly-->

    <!-- empty space so tooltip fits -->
    <h3>{{language_name}} treebanks</h3>

    <div class="jquery-ui-subaccordion-closed ui-accordion ui-widget ui-helper-reset ui-accordion-icons" role="tablist"> <!-- start of {{language_name}} treebank list -->
      {% for tbank in treebanks %}
      <div class="ui-accordion-header ui-helper-reset ui-state-default ui-corner-all" role="tab" aria-expanded="false" aria-selected="false" tabindex="-1"> <!-- start of {{language_name}} / {{tbank.treebank_code|default("Original",true)}} entry -->
        <span class="flagspan"></span>
        <span class="doublewidespan">{{tbank.treebank_code|default("Original",true)}}</span>
        <span class="widespan"><span class="hint--top hint--info" data-hint="{{tbank.counts.token|tsepk}} tokens {{tbank.counts.word|tsepk}} words {{tbank.counts.node|tsepk}} nodes {{tbank.counts.tree|tsepk}} sentences">{{tbank.counts.word|tsepk(use_k=true)}}</span></span>
        <span class="widespan">{{tbank.counts|tag_filter|safe}}</span>
        <!-- <span class="widespan">{{tbank.meta|annotation_filter|safe}}</span> -->
        <span class="doublewidespan">{{tbank.meta.genre|genre_filter|safe}}</span>
        <span class="widespan">{{tbank.meta.license|license_filter|safe}}</span>
        <span class="widespan">{{(tbank.score,tbank.stars)|stars_filter|safe}}</span>
      </div>
      <div class="ui-accordion-content ui-helper-reset ui-widget-content ui-corner-bottom" role="tabpanel" style="height: 149.8px;">

        {{tbank.meta.summary|default("Please add a summary section to the treebank readme file",true)}}

        <ul>
          <li>Contributors: {{tbank.meta.contributors|contributor_filter}} </li>
             <li>Repository <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/master">master</a> <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/dev">dev</a></li>
             <li><a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/blob/{{tbank.repo_branch}}/{{tbank.readme_file}}">README</a></li>
          <li><a href="treebanks/{{tbank.treebank_lcode_code}}/index.html">Treebank hub page</a></li>
          <li><a href="#download">Download</a></li>
        </ul>

        <p>&nbsp;</p>
      </div> <!-- end of {{language_name}} / {{tbank.treebank_code|default("Original",true)}} entry -->
      {% endfor %}
    </div> <!-- end of {{language_name}} treebank list -->

    {% if tbank_comparison %}
    See <a href="treebanks/{{tbank_comparison}}">here</a> for comparative statistics of {{language_name}} treebanks.
    {% endif %}

    <h3> Language documentation </h3>

    {% if language_hub %}
    See the <a href="{{language_code}}/index.html">language documentation page</a>.
    {% else %}
    The language hub documentation has not yet been created or ported from the UDv1 documentation.
    {% endif %}

  </div> <!-- end of {{language_name}} accordion body -->
