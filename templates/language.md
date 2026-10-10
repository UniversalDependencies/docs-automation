  <!-- start of {{language_name}} accordion row -->
  <details class="ud-accordion" name="ud-language-{{subset}}">
    <summary id="language-{% if subset != 'current' %}{{subset}}-{% endif %}{{language_code}}">
      <span class="flagspan"><img class="flag" src="flags/svg/{{flag}}.svg" alt="" loading="lazy" decoding="async" /></span>
      <span class="doublewidespan">{{language_name_short}}</span>
      <span class="widespan"><span class="hint--top hint--info" data-hint="{{treebanks|length}} treebank{% if treebanks|length > 1 %}s{% endif %}">{{treebanks|length}}</span></span>
      <span class="widespan"><span class="hint--top hint--info" data-hint="{{counts.token|tsepk}} tokens {{counts.word|tsepk}} words {{counts.node|tsepk}} nodes {{counts.tree|tsepk}} sentences">{{counts.word|tsepk(use_k=true)}}</span></span>
      <!-- English has so many genres that they no longer fit in doublewidespan. -->
      <span class="triplewidespan">{{genres|genre_filter|safe}}</span>
      <span class="triplewidespan">{{(language_family,language_genus)|family_filter|safe}}</span>
    </summary>
    <div class="ud-accordion-body">

    <h3>{{language_name}} treebanks</h3>

    <!-- start of {{language_name}} treebank list -->
    {% for tbank in treebanks %}
    <details class="ud-accordion ud-subaccordion" name="ud-treebank-{{subset}}-{{language_code}}">
      <summary>
        <span class="flagspan"></span>
        <span class="doublewidespan">{{tbank.treebank_code|default("Original",true)}}</span>
        <span class="widespan"><span class="hint--top hint--info" data-hint="{{tbank.counts.token|tsepk}} tokens {{tbank.counts.word|tsepk}} words {{tbank.counts.node|tsepk}} nodes {{tbank.counts.tree|tsepk}} sentences">{{tbank.counts.word|tsepk(use_k=true)}}</span></span>
        <span class="widespan">{{(tbank.counts,tbank.meta)|tag_filter|safe}}</span>
        <span class="widespan">{{tbank.meta.parallel|parallel_filter|safe}}</span>
        <span class="doublewidespan">{{tbank.meta.genre|genre_filter|safe}}</span>
        <span class="widespan">{{tbank.meta.license|license_filter|safe}}</span>
        <span class="widespan">{{(tbank.score,tbank.stars)|stars_filter|safe}}</span>
      </summary>
      <div class="ud-accordion-body">

        {{tbank.meta.summary|default("Please add a summary section to the treebank readme file",true)}}

        <ul>
          <li>Contributors: {{tbank.meta.contributors|contributor_filter}} </li>
             <li>Repository <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/master">master</a> <a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/tree/dev">dev</a></li>
             <li><a href="https://github.com/UniversalDependencies/{{tbank.repo_name}}/blob/{{tbank.repo_branch}}/{{tbank.readme_file}}">README</a></li>
          <li><a href="treebanks/{{tbank.treebank_lcode_code}}/index.html">Treebank hub page</a></li>
          <li><a href="#download">Download</a></li>
        </ul>

      </div>
    </details>
    {% endfor %}
    <!-- end of {{language_name}} treebank list -->

    {% if tbank_comparison %}
    See <a href="treebanks/{{tbank_comparison}}">here</a> for comparative statistics of {{language_name}} treebanks.
    {% endif %}

    <h3> Language documentation </h3>

    {% if language_hub %}
    See the <a href="{{language_code}}/index.html">language documentation page</a>.
    {% else %}
    The language hub documentation has not yet been created.
    {% endif %}

    </div>
  </details>
  <!-- end of {{language_name}} accordion row -->

