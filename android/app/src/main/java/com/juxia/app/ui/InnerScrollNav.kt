package com.juxia.app.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.juxia.app.ui.theme.FontSans

// 句栖 · 内层滚动导航（翻译自 InnerScrollNav.ets：长按到顶/到底，500ms）
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun InnerScrollNav(onTop: () -> Unit, onBottom: () -> Unit) {
    val t = appTokens()
    Row(
        Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 2.dp),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically
    ) {
        NavButton("↑ 长按到顶", t, onTop)
        NavButton("↓ 长按到底", t, onBottom)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NavButton(label: String, t: com.juxia.app.ui.theme.Tokens, action: () -> Unit) {
    Text(
        text = label,
        color = t.inkSoftColor,
        fontFamily = FontSans,
        fontSize = scaledSp(11),
        modifier = Modifier
            .clip(RoundedCornerShape(999.dp))
            .combinedClickable(onClick = {}, onLongClick = action)
            .padding(horizontal = 10.dp, vertical = 6.dp)
    )
}
